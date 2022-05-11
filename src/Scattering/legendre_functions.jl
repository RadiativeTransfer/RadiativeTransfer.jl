#=
 
This file defines helpful Legendre-related functions

=#

"""
    $(FUNCTIONNAME)(μ,Lmax)

Computes the normalized Π matrix elements with generalized spherical functions (normalized by sqrt((l-m)!/(l+m)!))). See eq 15 in Sanghavi 2014

- `μ` cos(θ) of angle θ
- `Lmax` max `l` Polynomial degree to be computed (m adjusted accordingly) 

The function returns matrices containing ``P_l^m(\\mu)``,  ``R_l^m(\\mu)``, ``-T_l^m(\\mu)``, all normalized by ``\\sqrt{\\frac{(l-m)!}{(l+m)!}}``
""" 
function compute_associated_legendre_PRT(μ,Lmax)
     # Note: P_l^m(μ) double-checked against Matlab, really hard to find other benchmarks for R and T!
     # Can probably be sped up but it can be pre-computed anyhow as angles μ and Lmax will be fixed per run
    FT = eltype(μ)

    # Create Arrays for the associate legendre coefficients (Siewert, eq. 10)
    P = (zeros(FT,length(μ),Lmax,Lmax));
    R = (zeros(FT,length(μ),Lmax,Lmax));
    T = (zeros(FT,length(μ),Lmax,Lmax));
    
    # Following Suniti Sanghavi code, looks somewhat different than Siewert as normalization is built in. 
    for  m=0:Lmax-1
        for l=m:Lmax-1
            for iμ in eachindex(μ)
                smu = sqrt(1.0 - μ[iμ]^2)
                cmu = μ[iμ] 
                #indices for arrays
                im = m+1;
                il = l+1;

                if m==0
                    if l==0 # then !eq.28a
                        P[iμ,il,im] = 1
                        R[iμ,il,im] = 0
                        T[iμ,il,im] = 0
                    elseif l==1 # then !eq.28b
                        P[iμ,il,im] = cmu
                        R[iμ,il,im] = 0
                        T[iμ,il,im] = 0
                    elseif l==2 # then !eq.28c, 29, 30
                        cA = 0.5*(3.0*cmu*cmu-1.0)
                        cB = 0.5*sqrt(1.5)*smu*smu

                        P[iμ,il,im] = cA
                        R[iμ,il,im] = cB
                        T[iμ,il,im] = 0.0
                    else #!eq.30, 31a, 31b
                        Y_lm1 = l-1
                        X_lm1 = l

                        P[iμ,il,im] = (P[iμ,il-1,im] * (2l-1) * cmu -  P[iμ,il-2,im] * Y_lm1 ) / X_lm1

                        Y_lm1 = sqrt( (l+1) * (l-3) )
                        X_lm1 = sqrt( l*l - 4 )

                        R[iμ,il,im] = (R[iμ,il-1,im] * (2*l-1) * cmu -  R[iμ,il-2,im] * Y_lm1) / X_lm1
                        T[iμ,il,im] = 0.0
                    end

                elseif m==1 # then
                    if l==1 # then !eq.32a
                        m1 = sqrt(0.5)
                        P[iμ,il,im] = m1*smu
                        R[iμ,il,im] = 0.0
                        T[iμ,il,im] = 0.0
                    elseif l==2 # then !eq.32b, 33a, 33b
                        m1 = sqrt(1/6)
                        cA = 3cmu*smu
                        cB = sqrt(1.5)*smu
                        P[iμ,il,im] = m1*cA
                        R[iμ,il,im] = -m1*cmu*cB
                        T[iμ,il,im] = m1*cB
                    else #!eq.34, 35a, 35b, 35c
                        m1 = sqrt((l-1)/(l+1))
                        m2 = m1 * sqrt( (l-2) / l )

                        Y_lm1 = (l-1+m)
                        X_lm1 = (l-m)

                        P[iμ,il,im] = (m1 * P[iμ,il-1,im] * (2l-1) * cmu 
                                    - m2 * P[iμ,il-2,im] * Y_lm1 ) / X_lm1

                        Z_lm1 = (2m * (2l-1) ) / (l * (l-1))
                        Y_lm1 = ( (l+m-1) / (l-1)) * sqrt( (l-3) * (l+1) )
                        X_lm1 = ( (l-m)   /  l   ) * sqrt( (l*l-4) )

                        R[iμ,il,im] = (m1*R[iμ,il-1,im] * (2l-1) * cmu 
                                    -m2 * R[iμ,il-2,im] * Y_lm1 +m1 * T[iμ,il-1,im] * Z_lm1 ) /X_lm1

                        T[iμ,il,im] = (m1*T[iμ,il-1,im] * (2l-1) * cmu
                                    -m2 * T[iμ,il-2,im] * Y_lm1 +m1 * R[iμ,il-1,im] * Z_lm1 ) /X_lm1
                    end
                else 
                    if l==m # then !eq.36, 37
                        fact1=1.0
                        fact2=1.0

                        sfull = smu
                        shalf = sfull/2
                        for i=1:m
                            fact1 = fact1*((2i-1)*sfull) / sqrt((i*(i+m)))
                            if i>2  #then
                                fact2 = fact2 * shalf * sqrt((m+i)/(i-2))
                            else
                                fact2 = fact2 * shalf
                            end
                        end
                        if smu>1e-8  # then
                            Km = (fact2)
                            Aii= Km * (1.0+cmu*cmu) / (smu*smu)
                            Aij= Km * (2cmu) / (smu*smu)
                        else
                            if m==2 # then
                                Aii=0.5
                                Aij=0.5
                            else
                                Aii=0.0
                                Aij=0.0
                            end
                        end
                        P[iμ,il,im] = fact1
                        R[iμ,il,im] =  Aii
                        T[iμ,il,im] = -Aij

                    elseif l==(m+1) # then !eq.38, 35a, 35b
                        # typo 1 and l??
                        m1 = sqrt((1)/(l+m))

                        Y_lm1 = (l-1+m)
                        X_lm1 = (l-m)

                        P[iμ,il,im] = ( m1 * P[iμ,il-1,im] * (2l-1) * cmu ) / X_lm1

                        Z_lm1 = (2m * (2l-1)) / (l*(l-1))
                        Y_lm1 = ((l+m-1) / (l-1)) * sqrt( (l-3) * (l+1) ) 
                        X_lm1 = ( (l-m) /l ) * sqrt(l*l-4)

                        R[iμ,il,im] = ( m1 * R[iμ,il-1,im] * (2l-1) * cmu 
                                    + m1 * T[iμ,il-1,im] * Z_lm1 ) / X_lm1
                        T[iμ,il,im] = ( m1 * T[iμ,il-1,im] * (2l-1) * cmu 
                                    + m1 * R[iμ,il-1,im] * Z_lm1 ) / X_lm1

                    else #!eq.38, 35a, 35b
                        m1 = sqrt( (l-m) / (l+m) )
                        m2 = m1 * sqrt( (l-m-1) / (l+m-1) )

                        Y_lm1 = (l-1+m)
                        X_lm1 = (l-m)

                        P[iμ,il,im] = ( m1 * P[iμ,il-1,im] * (2l-1) * cmu 
                                    - m2 * P[iμ,il-2,im] * Y_lm1 ) / X_lm1

                        Z_lm1 = (2m*(2l-1)) / (l*(l-1))
                        Y_lm1 = ( (l+m-1) / (l-1) ) * sqrt( (l-3) * (l+1) )
                        X_lm1 = ( (l-m) / l ) * sqrt( l*l-4 )

                        R[iμ,il,im] = ( m1 * R[iμ,il-1,im] * (2l-1) * cmu 
                                    - m2 * R[iμ,il-2,im] * Y_lm1  
                                    + m1 * T[iμ,il-1,im] * Z_lm1) / X_lm1

                        T[iμ,il,im] = ( m1 * T[iμ,il-1,im] * (2l-1) * cmu 
                                    - m2 * T[iμ,il-2,im] * Y_lm1
                                    + m1 * R[iμ,il-1,im] * Z_lm1) / X_lm1

                    end
                end
            end
       end
    end
    # Note: from Suniti's code, -T is actually computed, so I return the "true" T here:
    return P,R,-T
end


"""
$(FUNCTIONNAME)(μ, nmax, π, τ)
Computes the associated Legendre functions  amplitude functions `π` and `τ` in Mie theory (stored internally). See eq 6 in Sanghavi 2014
- `μ` cosine of the scattering angle
- `nmax` max number of legendre terms (depends on size parameter, see [`get_n_max`](@ref))
Functions returns `π` and `τ` (of size `[nmax,length(μ)]`)
"""
function compute_mie_π_τ(μ, nmax)
    FT = eltype(μ)
    # Allocate arrays:
    π_ = zeros(FT,length(μ),nmax)
    τ_ = zeros(FT,length(μ),nmax)

    # BH book, pages 94-96:
    π_[:,1] .= 1.0;
    π_[:,2] .= 3μ;
    τ_[:,1] .= μ;
    # This is equivalent to 3*cos(2*acos(μ))
    τ_[:,2] .= 6μ.^2 .-3;
    for n=2:nmax-1
        for i in eachindex(μ)
            π_[i,n+1] = ((2n + 1) * μ[i] * π_[i,n] - (n+1) * π_[i,n-1]) / n 
            τ_[i,n+1] = (n+1) * μ[i] * π_[i,n+1] - (n+2)*π_[i,n]
            # @show n+1,μ[i], π_[n+1,i], τ_[n+1,i], π_[n,i]
        end
    end
    return π_, τ_
end

"""
$(FUNCTIONNAME)(x,nmax)
Returns the associated legendre functions Pᵢ, P²ᵢ, R²ᵢ, and T²ᵢ as a function of x and i=1:nmax 
- `x` array of locations to be evaluated [-1,1]
- `nmax` max number of legendre terms (depends on size parameter, see [`get_n_max`](@ref))
The function returns `Pᵢ`, `P²ᵢ`, `R²ᵢ`, and `T²ᵢ`, for a size distribution, this can be pre-computed with nmax derived from the maximum size parameter.
"""
function compute_legendre_poly(x::Array{FT},nmax) where FT
    #FT = eltype(x)
    @assert nmax > 1
    #@assert size(P) == (nmax,length(x))
    P⁰ = zeros(FT,length(x),nmax);
    P² = zeros(FT,length(x),nmax);
    R² = zeros(FT,length(x),nmax);
    T² = zeros(FT,length(x),nmax);
    # 0th Legendre polynomial, a constant
    P⁰[:,1] .= 1;
    P²[:,1] .= 0;
    R²[:,1] .= 0;
    T²[:,1] .= 0; 
    # 1st Legendre polynomial, x
    P⁰[:,2]  = x;
    P²[:,2] .= 0;
    R²[:,2] .= 0;
    T²[:,2] .= 0;

    # 2nd Legendre polynomial, x
    #P¹[2,:] = x;
    if nmax >2
        P²[:,3] .= 3   * (1 .- x.^2);
        R²[:,3] .= sqrt(1.5) * (1 .+ x.^2);
        T²[:,3] .= sqrt(6) * x;
    end
    for n=2:nmax-1
        for i in eachindex(x)
            l = n-1;
            P⁰[i,n+1] = ((2l + 1) * x[i] * P⁰[i,n] - l * P⁰[i,n-1])/(l+1)
            if n>2
                ia = (2l+1) * x[i];
	            ib = sqrt( (l+2) * (l-2) ) * (l+2) / (l);
	            ic = 4.0 * (2l+1) / ( (l+1)*l );
	            id = sqrt( (l+3) * (l-1) ) * (l-1) / (l+1);
                P²[i,n+1] = ( ia * P²[i,n] - (l+2) * P²[i,n-1] ) / (l-1)
                R²[i,n+1] = ( ia * R²[i,n] - ib * R²[i,n-1] - ic * T²[i,n] ) / id;
	            T²[i,n+1] = ( ia * T²[i,n] - ib * T²[i,n-1] - ic * R²[i,n] ) / id;
            end  
        end
    end
    return P⁰, P², R², T²
end

# Following Milthorpe, 2014, includes the Condon–Shortley phase
function compute_legendre_P(μ , Lmax)
    FT = eltype(μ)
    da = zeros(FT,Lmax+1,Lmax+1)
    sintheta = sqrt(1.0 .- μ*μ)
    temp = sqrt(0.5/π)
    da[1,1] = sqrt(0.5/π);
    if Lmax > 0
        SQRT3 = sqrt(3.0)
        da[1,2] = μ * SQRT3 * temp
        SQRT3DIV2 = -sqrt(3.0 / 2.0)
        temp = SQRT3DIV2 * sintheta * temp
        da[2,2] = temp

        for l=2:Lmax
            il = l+1
            for m=0:l-2
                im = m+1
                A =  sqrt( (4l^2-1) / (l^2 - m^2) )
                B = -sqrt( ((l-1)^2-m^2) / (4*(l-1)^2 - 1) )  
                da[il,im] = A * (μ * da[il-1,im] + B * da[il-2,im] )
            end
            da[il-1,il] = μ * sqrt(2*(l-1)+3) * temp;
            temp = -sqrt(1 + 0.5/l ) * sintheta * temp
            da[il,il] = temp
        end
    end
    ll = collect(Float64,0:Lmax)
    ll = sqrt.( (2*ll .+ 1)/2π)

    return da./ll'
end



