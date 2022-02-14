function constructCoreOpticalProperties(RS_type, iBand, m, model)
    @unpack τ_rayl, τ_aer, τ_abs, aerosol_optics, greek_rayleigh  = model
    @assert all(iBand .≤ length(τ_rayl)) "iBand exceeded number of bands"
    FT = eltype(τ_rayl)
    pol_type = model.params.polarization_type
    # Do this in CPU space only first:
    arr_type = Array
    # Quadrature points:
    μ = Array(model.quad_points.qp_μ )
    # Number of Aerosols:
    nAero = size(τ_aer[iBand[1]],1)
    nZ    = length(τ_rayl[1][:])
    # Rayleigh Z matrix:
    Rayl𝐙⁺⁺, Rayl𝐙⁻⁺ = Scattering.compute_Z_moments(pol_type, μ, 
                                                    greek_rayleigh, m, 
                                                    arr_type = arr_type);

    band_layer_props    = [];
    band_fScattRayleigh = [];
    
    for iB in iBand
        #@show τ_rayl[iB][:]
        #,  ones(FT, length(RS_type.bandSpecLim[iB]))
        #@show RS_type.ϖ_Cabannes
        #@show τ_rayl
        rayl = CoreScatteringOpticalProperties.(
                τ_rayl[iB][:], 
                [RS_type.ϖ_Cabannes[iB]], 
                [Rayl𝐙⁺⁺], [Rayl𝐙⁻⁺])
        #@show size(rayl)
        # Initiate combined properties with rayleigh
        combo = rayl

        # Loop over all aerosol types:
        for i=1:nAero
            # Precomute Z matrices per type (constant per layer)
            #@show iB,i
            AerZ⁺⁺, AerZ⁻⁺ = Scattering.compute_Z_moments(
                                pol_type, μ, 
                                aerosol_optics[iB][i].greek_coefs, 
                                m, arr_type=arr_type)
            # Generate Core optical properties for Aerosols i
            aer   = createAero.(τ_aer[iB][i,:], 
                                [aerosol_optics[iB][i]], 
                                [AerZ⁺⁺], [AerZ⁻⁺])
            # Mix with previous Core Optical Properties
            #@show combo[1].ϖ   , aer[1].ϖ
            combo = combo .+ aer
        end

        # Somewhere here we can add canopy later as well!
        ###

        # fScattRayleigh:
        #@show rayl[1].τ * rayl[1].ϖ, combo[1].τ
        # Assume ϖ of 1 for Rayleight here:
        fScattRayleigh = [rayl[i].τ  / combo[i].τ for i=1:length(combo)]
        #@show fScattRayleigh
        # Create Core Optical Properties merged with trace gas absorptions:
        push!(band_layer_props,
                combo .+ 
                [CoreAbsorptionOpticalProperties(τ_abs[iB][:,i]) for i=1:length(combo)])
        push!(band_fScattRayleigh,fScattRayleigh)
        #aType = array_type(model.params.architecture)
        #combo2 = [CoreScatteringOpticalProperties(aType(combo[i].τ),aType(combo[i].ϖ), aType(combo[i].Z⁺⁺), aType(combo[i].Z⁻⁺)) for i in eachindex(combo)]
        # Need to check how to convert to GPU later as well!
        #return combo,fScattRayleigh
    end

    layer_opt = []
    fscat_opt = []
    for iz = 1:nZ
        push!(layer_opt, prod([band_layer_props[i][iz] for i=1:length(iBand)]));
        push!(fscat_opt, expandBandScalars(RS_type,[band_fScattRayleigh[i][iz] for i=1:length(iBand)]));
    end
    # For now just one band_fScattRayleigh
    return layer_opt, fscat_opt # Suniti: this needs to be modified because Rayleigh scattering fraction varies dramatically with wavelength
end

function createAero(τAer, aerosol_optics, AerZ⁺⁺, AerZ⁻⁺)
    @unpack fᵗ, ω̃ = aerosol_optics
    τ_mod = (1-fᵗ * ω̃ ) * τAer;
    ϖ_mod = (1-fᵗ) * ω̃/(1-fᵗ * ω̃)
    CoreScatteringOpticalProperties(τ_mod, ϖ_mod,AerZ⁺⁺, AerZ⁻⁺)
end

# Extract scattering definitions and integrated absorptions for the source function!
function extractEffectiveProps(
                                lods::Array#{CoreScatteringOpticalProperties{FT},1}
                                ) #where FT

    FT = eltype(lods[1].τ)
    nSpec = length(lods[1].τ)
    nZ    = length(lods)
    # First the Scattering Interfaces:
    scattering_interface = ScatteringInterface_00()
    scattering_interfaces_all = []
    τ_sum_all = zeros(FT,nSpec,nZ+1)
    
    for iz =1:nZ
        # Need to check max entries in Z matrices here as well later!
        scatter = maximum(lods[iz].τ .* lods[iz].ϖ) > 2eps(FT)
        scattering_interface = get_scattering_interface(scattering_interface, scatter, iz)
        push!(scattering_interfaces_all, scattering_interface)
        τ_sum_all[:,iz+1] = τ_sum_all[:,iz] + lods[iz].τ 
    end
    return scattering_interfaces_all, τ_sum_all
end

function expandOpticalProperties(in::CoreScatteringOpticalProperties, arr_type)
    @unpack τ, ϖ, Z⁺⁺, Z⁻⁺ = in 
    @assert length(τ) == length(ϖ) "τ and ϖ sizes need to match"
    if size(Z⁺⁺,3) == 1
        Z⁺⁺ = repeat(Z⁺⁺,1,1,length(τ))
        Z⁻⁺ = repeat(Z⁻⁺,1,1,length(τ))
        return CoreScatteringOpticalProperties(arr_type(τ), arr_type(ϖ), arr_type(Z⁺⁺), arr_type(Z⁻⁺)) 
    else
        @assert size(Z⁺⁺,3) ==  length(τ) "Z and τ dimensions need to match "
        CoreScatteringOpticalProperties(arr_type(τ), arr_type(ϖ), arr_type(Z⁺⁺), arr_type(Z⁻⁺)) 
    end
end

function expandBandScalars(RS_type, x)
    out = zeros(eltype(x),sum([length(RS_type.bandSpecLim[iB]) for iB in RS_type.iBand]))
    for iB in RS_type.iBand
        out[RS_type.bandSpecLim[iB]] .= expandScalar(x[iB],length(RS_type.bandSpecLim[iB]))
    end
    return out
end

expandScalar(x,n) = x*ones(n);