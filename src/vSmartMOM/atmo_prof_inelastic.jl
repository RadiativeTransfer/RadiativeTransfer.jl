#=

This file contains functions that are related to atmospheric profile calculations

=#

"Compute pressure levels, vmr, vcd for atmospheric profile, given p_half, T, q"
function compute_atmos_profile_fields(T, p_half::AbstractArray, q, vmr; g₀=9.8196)

    # Floating type to use
    FT = eltype(T)
    
    # Calculate full pressure levels
    p_full = (p_half[2:end] + p_half[1:end-1]) / 2

    # Dry and wet mass
    dry_mass = 28.9647e-3  / Nₐ  # in kg/molec, weighted average for N2 and O2
    wet_mass = 18.01528e-3 / Nₐ  # just H2O
    ratio = dry_mass / wet_mass 
    n_layers = length(T)

    # Also get a VMR vector of H2O (volumetric!)
    vmr_h2o = zeros(FT, n_layers, )
    vcd_dry = zeros(FT, n_layers, )
    vcd_h2o = zeros(FT, n_layers, )

    # Now actually compute the layer VCDs
    for i = 1:n_layers 
        Δp = p_half[i + 1] - p_half[i]
        vmr_h2o[i] = q[i] * ratio
        vmr_dry = 1 - vmr_h2o[i]
        M  = vmr_dry * dry_mass + vmr_h2o[i] * wet_mass
        vcd_dry[i] = vmr_dry * Δp / (M * g₀ * 100.0^2) * 100  # includes m2->cm2
        vcd_h2o[i] = vmr_h2o[i] * Δp / (M * g₀ * 100^2) * 100
    end

    new_vmr = Dict{String, Union{Real, Vector}}()

    for molec_i in keys(vmr)
        if vmr[molec_i] isa AbstractArray
            
            pressure_grid = collect(range(minimum(p_full), maximum(p_full), length=length(vmr[molec_i])))
            interp_linear = LinearInterpolation(pressure_grid, vmr[molec_i])
            new_vmr[molec_i] = [interp_linear(x) for x in p_full]
        else
            new_vmr[molec_i] = vmr[molec_i]
        end
    end

    return p_full, p_half, vmr_h2o, vcd_dry, vcd_h2o, new_vmr

end

"From a yaml file, get the stored fields (psurf, T, q, ak, bk), calculate derived fields, 
and return an AtmosphericProfile object" 
function read_atmos_profile(file_path::String)

    # Make sure file is yaml type
    @assert endswith(file_path, ".yaml") "File must be yaml"

    # Read in the data and pass to compute fields
    params_dict = YAML.load_file(file_path)

    # Validate the parameters before doing anything else
    # validate_atmos_profile(params_dict)

    T = convert.(Float64, params_dict["T"])
    
    # Calculate derived fields
    if ("ak" in keys(params_dict))
        psurf = convert(Float64, params_dict["p_surf"])
        q     = convert.(Float64, params_dict["q"])
        ak    = convert.(Float64, params_dict["ak"])
        bk    = convert.(Float64, params_dict["bk"])
        p_half = (ak + bk * psurf)
        p_full, p_half, vmr_h2o, vcd_dry, vcd_h2o = compute_atmos_profile_fields(T, p_half, q, Dict())
    elseif ("q" in keys(params_dict))
        p_half = convert(Float64, params_dict["p_half"])
        psurf = p_half[end]
        q      = convert.(Float64, params_dict["q"])
        p_full, p_half, vmr_h2o, vcd_dry, vcd_h2o = compute_atmos_profile_fields(T, p_half, q, Dict())
    else
        p_half = convert.(Float64, params_dict["p_half"])
        psurf = p_half[end]
        q = zeros(length(T))
        p_full, p_half, vmr_h2o, vcd_dry, vcd_h2o = compute_atmos_profile_fields(T, p_half, q, Dict())
    end

    # Convert vmr to appropriate type
    vmr = convert(Dict{String, Union{Real, Vector}}, params_dict["vmr"])

    # Return the atmospheric profile struct
    return AtmosphericProfile(T, q, p_full, p_half, vmr_h2o, vcd_dry, vcd_h2o, vmr)

end

"Reduce profile dimensions by re-averaging to near-equidistant pressure grid"
function reduce_profile(n::Int, profile::AtmosphericProfile{FT}) where {FT}

    # Can only reduce the profile, not expand it
    @assert n < length(profile.T)

    # Unpack the profile vmr
    @unpack vmr = profile

    # New rough half levels (boundary points)
    a = range(0, maximum(profile.p_half), length=n+1)

    # Matrices to hold new values
    T = zeros(FT, n);
    q = zeros(FT, n);
    p_full = zeros(FT, n);
    p_half = zeros(FT, n+1);
    vmr_h2o  = zeros(FT, n);
    vcd_dry  = zeros(FT, n);
    vcd_h2o  = zeros(FT, n);

    # Loop over target number of layers
    for i = 1:n

        # Get the section of the atmosphere with the i'th section pressure values
        ind = findall(a[i] .< profile.p_full .<= a[i+1]);

        # Set the pressure levels accordingly
        p_half[i] = profile.p_half[ind[1]]
        p_half[i+1] = profile.p_half[ind[end]]

        # Re-average the other parameters to produce new layers
        p_full[i] = mean(profile.p_half[ind])
        T[i] = mean(profile.T[ind])
        q[i] = mean(profile.q[ind])
        vmr_h2o[i] = mean(profile.vmr_h2o[ind])
        vcd_dry[i] = sum(profile.vcd_dry[ind])
        vcd_h2o[i] = sum(profile.vcd_h2o[ind])
    end

    new_vmr = Dict{String, Union{Real, Vector}}()

    for molec_i in keys(vmr)
        if profile.vmr[molec_i] isa AbstractArray
            
            pressure_grid = collect(range(minimum(p_full), maximum(p_full), length=length(profile.vmr[molec_i])))
            interp_linear = LinearInterpolation(pressure_grid, vmr[molec_i])
            new_vmr[molec_i] = [interp_linear(x) for x in p_full]
        else
            new_vmr[molec_i] = profile.vmr[molec_i]
        end
    end

    return AtmosphericProfile(T, p_full, q, p_half, vmr_h2o, vcd_dry, vcd_h2o, new_vmr)
end

"""
    $(FUNCTIONNAME)(psurf, λ, depol_fct, vcd_dry)

Returns the Rayleigh optical thickness per layer at reference wavelength `λ` (N₂,O₂ atmosphere, i.e. terrestrial)

Input: 
    - `psurf` surface pressure in `[hPa]`
    - `λ` wavelength in `[μm]`
    - `depol_fct` depolarization factor
    - `vcd_dry` dry vertical column (no water) per layer
"""
function getRayleighLayerOptProp(psurf, λ, depol_fct, vcd_dry) 
    FT = eltype(λ)
    # Total vertical Rayleigh scattering optical thickness 
    tau_scat = FT(0.00864) * (psurf / FT(1013.25)) * λ^(-FT(3.916) - FT(0.074) * λ - FT(0.05) / λ) 
    tau_scat = tau_scat * (FT(6.0) + FT(3.0) * depol_fct) / (FT(6.0)- FT(7.0) * depol_fct)
    Nz = length(vcd_dry)
    τRayl = zeros(FT,Nz)
    k = tau_scat / sum(vcd_dry)
    for i = 1:Nz
        τRayl[i] = k * vcd_dry[i]
    end

    return convert.(FT, τRayl)
end

# TODO_Suniti
"""
    $(FUNCTIONNAME)(RS_type, λ, grid_in)

Returns the Raman SSA per layer at reference wavelength `λ` from nearby source wavelengths for RRS and a (currently) single incident wavelength for VRS/RVRS
(N₂,O₂ atmosphere, i.e. terrestrial)

Input: 
    - `RS_type` Raman scattering type (RRS/RVRS/VRS)
    - `λ` wavelength in `[μm]`
    - `grid_in` wavenumber grid with equidistant gridpoints
"""
function getRamanLayerSSA(RS_type::VS_0to1, T, λ, grid_in)
    @unpack n2,o2 =  RS_type
    #n2, o2 = getRamanAtmoConstants(1.e7/λ, T)
    # determine Rayleigh scattering cross-section at single monochromatic wavelength λ of the spectral band (assumed constant throughout the band)
    compute_optical_Rayl!(atmo_σ_Rayl, λ, n2, o2)
    # determine RRS cross-sections to λ₀ from nSpecRaman wavelengths around λ₀  
    compute_optical_VRS_0to1!(grid_in, index_VRSgrid_out, atmo_σ_VRS_0to1, index_RVRSgrid_out, atmo_σ_RVRS_0to1, λ, n2, o2)
    # declare ϖ_Raman to be a grid of length raman grid
    ϖ_VRS = atmo_σ_VRS_0to1/atmo_σ_Rayl
    i_VRS = index_VRSgrid_out
    ϖ_RVRS = atmo_σ_RVRS_0to1/atmo_σ_Rayl
    i_RVRS = index_RVRSgrid_out
    return ϖ_RVRS, i_RVRS, ϖ_VRS, i_VRS 
end
function getRamanLayerSSA(RS_type::VS_1to0, T, λ, grid_in)
    @unpack n2,o2 =  RS_type
    #n2, o2 = getRamanAtmoConstants(1.e7/λ, T)
    # determine Rayleigh scattering cross-section at single monochromatic wavelength λ of the spectral band (assumed constant throughout the band)
    compute_optical_Rayl!(atmo_σ_Rayl, λ, n2, o2)
    # determine RRS cross-sections to λ₀ from nSpecRaman wavelengths around λ₀  
    compute_optical_VRS_1to0!(grid_in, index_VRSgrid_out, atmo_σ_VRS_1to0, index_RVRSgrid_out, atmo_σ_RVRS_1to0, λ, n2, o2)
    # declare ϖ_Raman to be a grid of length raman grid
    ϖ_VRS = atmo_σ_VRS_1to0/atmo_σ_Rayl
    i_VRS = index_VRSgrid_out
    ϖ_RVRS = atmo_σ_RVRS_1to0/atmo_σ_Rayl
    i_RVRS = index_RVRSgrid_out
    return ϖ_RVRS, i_RVRS, ϖ_VRS, i_VRS
end

function getRamanLayerSSA(RS_type::RRS, T, λ, grid_in) 
    @unpack n2,o2 =  RS_type
    #n2, o2 = getRamanAtmoConstants(1.e7/λ, T)
    # determine Rayleigh scattering cross-section at central wavelength λ of the spectral band (assumed constant throughout the band)
    compute_optical_Rayl!(atmo_σ_Rayl, λ, n2, o2)
    # determine RRS cross-sections to λ₀ from nSpecRaman wavelengths around λ₀  
    compute_optical_RRS!(grid_in, index_raman_grid, atmo_σ_RRS, λ, n2, o2)
    # declare ϖ_Raman to be a grid of length raman grid
    ϖ_RRS = atmo_σ_RRS[end:-1:1]/atmo_σ_Rayl #the grid gets inverted because the central wavelength is now seen as the recipient of RRS from neighboring source wavelengths
    i_RRS = index_raman_grid[end:-1:1]
    return ϖ_RRS, i_RRS
end

"""
    $(FUNCTIONNAME)(total_τ, p₀, σp, p_half)
    
Returns the aerosol optical depths per layer using a Gaussian distribution function with p₀ and σp on a pressure grid
"""
function getAerosolLayerOptProp(total_τ, p₀, σp, p_half)

    # Need to make sure we can also differentiate wrt σp (FT can be Dual!)
    FT = eltype(p₀)
    Nz = length(p_half)
    ρ = zeros(FT,Nz)

    for i = 2:Nz
        dp = p_half[i] - p_half[i - 1]
        ρ[i] = (1 / (σp * sqrt(2π))) * exp(-(p_half[i] - p₀)^2 / (2σp^2)) * dp
    end
    Norm = sum(ρ)
    τAer  =  (total_τ / Norm) * ρ
    return convert.(FT, τAer)
end

"""
    $(FUNCTIONNAME)(τRayl, fscattRayl, τAer,  aerosol_optics, Rayl𝐙⁺⁺, Rayl𝐙⁻⁺, Aer𝐙⁺⁺, Aer𝐙⁻⁺, τ_abs, arr_type)

Computes the composite layer single scattering parameters (τ, ϖ, Z⁺⁺, Z⁻⁺)

Returns:
    - `τ`, `ϖ`   : only Rayleigh scattering and aerosol extinction, no gaseous absorption (no wavelength dependence)
    - `τ_λ`,`ϖ_λ`: Rayleigh scattering + aerosol extinction + gaseous absorption (wavelength dependent)
    - `Z⁺⁺`,`Z⁻⁺`: Composite Phase matrix (weighted average of Rayleigh and aerosols)
    - `fscattRayl` Rayleigh fraction of total scattering optical thickness 
Arguments:
    - `τRay` layer optical depth for Rayleigh
    - `τAer` layer optical depth for Aerosol(s) (vector)
    - `aerosol_optics` array of aerosol optics struct
    - `Rayl𝐙⁺⁺` Rayleigh 𝐙⁺⁺ phase matrix (2D)
    - `Rayl𝐙⁻⁺` Rayleigh 𝐙⁻⁺ phase matrix (2D)
    - `Aer𝐙⁺⁺` Aerosol 𝐙⁺⁺ phase matrix (3D)
    - `Aer𝐙⁻⁺` Aerosol 𝐙⁻⁺ phase matrix (3D)
    - `τ_abs` layer absorption optical depth array (per wavelength) by gaseous absorption
"""
function construct_atm_layer(τRayl, τAer, aerosol_optics, Rayl𝐙⁺⁺, Rayl𝐙⁻⁺, Aer𝐙⁺⁺, Aer𝐙⁻⁺, τ_abs, arr_type)
    FT = eltype(τRayl)
    nAer = length(aerosol_optics)

    # Fix Rayleigh SSA to 1
    ϖRayl = FT(1)

    @assert length(τAer) == nAer "Sizes don't match"

    τ = FT(0)
    ϖ = FT(0)
    A = FT(0)
    Z⁺⁺ = similar(Rayl𝐙⁺⁺); 
    Z⁻⁺ = similar(Rayl𝐙⁺⁺);

    if (τRayl + sum(τAer)) < eps(FT)
        fill!(Z⁺⁺, 0); fill!(Z⁻⁺, 0);
        return FT(0), FT(1), Z⁺⁺, Z⁻⁺
    end
 
    τ += τRayl
    ϖ += τRayl * ϖRayl
    A += τRayl * ϖRayl

    Z⁺⁺ = τRayl * ϖRayl * Rayl𝐙⁺⁺
    Z⁻⁺ = τRayl * ϖRayl * Rayl𝐙⁻⁺

    for i = 1:nAer
        τ   += τAer[i]
        ϖ   += τAer[i] * aerosol_optics[i].ω̃
        A   += τAer[i] * aerosol_optics[i].ω̃ * (1 - aerosol_optics[i].fᵗ)
        Z⁺⁺ += τAer[i] * aerosol_optics[i].ω̃ * (1 - aerosol_optics[i].fᵗ) * Aer𝐙⁺⁺[:,:,i]
        Z⁻⁺ += τAer[i] * aerosol_optics[i].ω̃ * (1 - aerosol_optics[i].fᵗ) * Aer𝐙⁻⁺[:,:,i]
    end
    
    Z⁺⁺ /= A
    Z⁻⁺ /= A
    A /= ϖ
    ϖ /= τ
    
    # Rescaling composite SSPs according to Eqs. A.3 of Sanghavi et al. (2013) or Eqs.(8) of Sanghavi & Stephens (2015)
    τ *= (FT(1) - (FT(1) - A) * ϖ)
    ϖ *= A / (FT(1) - (FT(1) - A) * ϖ)#Suniti
    fscattRayl = τRayl*ϖRayl/τ
    # Adding absorption optical depth / albedo:
    τ_λ = τ_abs .+ τ    
    ϖ_λ = (τ .* ϖ) ./ τ_λ

    #TODO_Suniti
    # define inelastic SSA of the layer with respect to the total layer optical thickness
    @show τRayl,ϖRayl,τ, fscattRayl
    return Array(τ_λ), Array(ϖ_λ), τ, ϖ, fscattRayl, Array(Z⁺⁺), Array(Z⁻⁺)
end

#TODO_Suniti
"When performing RT_run, this function pre-calculates properties for all layers, before any Core RT is performed"
function construct_all_atm_layers(FT, nSpec, Nz, NquadN, τRayl, τAer, aerosol_optics, Rayl𝐙⁺⁺, Rayl𝐙⁻⁺, Aer𝐙⁺⁺, Aer𝐙⁻⁺, τ_abs, arr_type, qp_μ, μ₀, m)

    FT_ext   = eltype(τRayl)
    FT_phase = eltype(Rayl𝐙⁺⁺)
    @show FT_ext, FT_phase
    # Empty matrices to hold all values
    τ_λ_all   = zeros(FT_ext, nSpec, Nz)
    ϖ_λ_all   = zeros(FT_ext, nSpec, Nz)
    τ_all     = zeros(FT_ext, Nz)
    ϖ_all     = zeros(FT_ext, Nz)
    Z⁺⁺_all   = zeros(FT_phase, NquadN, NquadN, Nz)
    Z⁻⁺_all   = zeros(FT_phase, NquadN, NquadN, Nz)
    
    dτ_max_all  = zeros(FT_ext, Nz)
    dτ_all      = zeros(FT_ext, Nz)
    ndoubl_all  = zeros(Int64, Nz)
    dτ_λ_all    = zeros(FT_ext, nSpec, Nz)
    expk_all    = zeros(FT_ext, nSpec, Nz)
    scatter_all = zeros(Bool, Nz)

    for iz=1:Nz
        
        # Construct atmospheric properties
        τ_λ_all[:, iz], ϖ_λ_all[:, iz], τ_all[iz], ϖ_all[iz], Z⁺⁺_all[:,:,iz], Z⁻⁺_all[:,:,iz] = construct_atm_layer(τRayl[iz], τAer[:,iz], aerosol_optics, Rayl𝐙⁺⁺, Rayl𝐙⁻⁺, Aer𝐙⁺⁺, Aer𝐙⁻⁺, τ_abs[:,iz], arr_type)

        # Compute doubling number
        dτ_max_all[iz] = minimum([τ_all[iz] * ϖ_all[iz], FT(0.001) * minimum(qp_μ)])
        dτ_all[iz], ndoubl_all[iz] = doubling_number(dτ_max_all[iz], τ_all[iz] * ϖ_all[iz]) #Suniti

        # Compute dτ vector
        dτ_λ_all[:, iz] = (τ_λ_all[:, iz] ./ (FT(2)^ndoubl_all[iz]))
        #@show maximum(dτ_λ_all[:,iz])
        expk_all[:, iz] = exp.(-dτ_λ_all[:, iz] /μ₀) #Suniti
        
        # Determine whether there is scattering
        scatter_all[iz] = (  sum(τAer[:,iz]) > 1.e-8 || 
                          (( τRayl[iz] > 1.e-8 ) && (m < 3))) ? 
                            true : false
    end

    # Compute sum of optical thicknesses of all layers above the current layer
    τ_sum_all = accumulate(+, τ_λ_all, dims=2)

    # First start with all zeros
    # At the bottom of the atmosphere, we have to compute total τ_sum (bottom of lowest layer), for the surface interaction
    τ_sum_all = hcat(zeros(FT, size(τ_sum_all[:,1])), τ_sum_all)

    # Starting scattering interface (None for both added and composite)
    scattering_interface = ScatteringInterface_00()
    scattering_interfaces_all = []

    for iz = 1:Nz
        # Whether there is scattering in the added layer, composite layer, neither or both
        scattering_interface = get_scattering_interface(scattering_interface, scatter_all[iz], iz)
        push!(scattering_interfaces_all, scattering_interface)
    end

    return ComputedAtmosphereProperties(τ_λ_all, ϖ_λ_all, τ_all, ϖ_all, Z⁺⁺_all, Z⁻⁺_all, dτ_max_all, dτ_all, ndoubl_all, dτ_λ_all, expk_all, scatter_all, τ_sum_all, scattering_interfaces_all)
end

"Given the CrossSectionModel, the grid, and the AtmosphericProfile, fill up the τ_abs array with the cross section at each layer
(using pressures/temperatures) from the profile" 
function compute_absorption_profile!(τ_abs::Array{FT,2}, 
                                     hitran_data::HitranTable, 
                                     broadening_function::AbstractBroadeningFunction, 
                                     wing_cutoff, 
                                     CEF::AbstractComplexErrorFunction, 
                                     architecture,
                                     vmr,
                                     grid,
                                     profile::AtmosphericProfile,
                                     ) where FT <: AbstractFloat

    # The array to store the cross-sections must be same length as number of layers
    @assert size(τ_abs,2) == length(profile.p_full)

    @showprogress 1 for iz in 1:length(profile.p_full)

        # Pa -> hPa
        p = profile.p_full[iz]
        T = profile.T[iz]

        # Either use the current layer's vmr, or use the uniform vmr
        vmr_curr = vmr isa AbstractArray ? vmr[iz] : vmr




        # Create absorption model with parameters
        absorption_model = make_hitran_model(hitran_data, 
                                             broadening_function, 
                                             wing_cutoff = wing_cutoff, 
                                             CEF = CEF, 
                                             architecture = architecture, 
                                             vmr = vmr_curr)

        # Changed index order
        τ_abs[:,iz] += Array(absorption_cross_section(absorption_model, grid, p, T)) * profile.vcd_dry[iz] * vmr_curr
    end
    
end
