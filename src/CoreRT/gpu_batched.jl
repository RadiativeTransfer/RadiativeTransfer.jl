#=

This file contains implementations of batched linear algebra code

=#

"Given 3D CuArrays A and B, fill in X[:,:,k] = A[:,:,k] \\ B[:,:,k]" 
function batch_solve!(X::CuArray{FT,3}, A::CuArray{FT,3}, B::CuArray{FT,3}) where {FT}

    # Temporary factorization matrix
    temp = similar(A)

    # LU-factorize A
    pivot, info   = CUBLAS.getrf_strided_batched!(A, true);
    synchronize()

    # Invert LU factorization of A
    CUBLAS.getri_strided_batched!(A, temp, pivot);

    # X = inv(A) * B
    NNlib.batched_mul!(X, temp, B)
    synchronize()

end

"Given 3D Julia Arrays A and B, fill in X[:,:,k] = A[:,:,k] \\ B[:,:,k]" 
function batch_solve!(X::AbstractArray{FT,3}, A::AbstractArray{FT,3}, B::AbstractArray{FT,3}) where {FT}
    for i = 1:size(A, 3)
        @views ldiv!(X[:,:,i], qr!(A[:,:,i]), B[:,:,i])
    end
end

"Given 3D CuArray A, fill in X[:,:,k] = A[:,:,k] \\ I" 
function batch_inv!(X::CuArray{FT,3}, A::CuArray{FT,3}) where {FT}

    # LU-factorize A
    pivot, info   = CUBLAS.getrf_strided_batched!(A, true);synchronize()
    # Invert LU factorization of A
    CUBLAS.getri_strided_batched!(A, X, pivot); synchronize()
end


"Given 3D Julia Array A, fill in X[:,:,k] = A[:,:,k] \\ I" 
function batch_inv!(X::AbstractArray{FT,3}, A::AbstractArray{FT,3}) where {FT}
    for i = 1:size(A, 3)
        @views X[:,:,i] = A[:,:,i]\I;
    end
end

"Batched matrix multiply (overwrite NNlib definition)"
function batched_mul(A::CuArray{FT,3}, B::CuArray{FT,3}) where {FT}
    CUBLAS.gemm_strided_batched('N', 'N', A, B)
end

"Define batched matrix multiply for GPU and Duals"
function batched_mul(A::CuArray{ForwardDiff.Dual{T,V,N},3}, B::CuArray{ForwardDiff.Dual{T,V,N},3}) where {T,V,N}
    # Extract values:
    Av = ForwardDiff.value.(A)
    Bv = ForwardDiff.value.(B)
    # Use strided batch for A*B (defined as gemm_strided_batched):
    Cv = Av ⊠ Bv
    # Compute derivatives ∂(AB)/∂x = A * ∂B/∂x + ∂A/∂x * B;
    dABdx = [Av ⊠ ForwardDiff.partials.(B,i) + ForwardDiff.partials.(A,i) ⊠ Bv for i=1:N];
    dABdx = ForwardDiff.Partials.(tuple.(dABdx...));
    return eltype(A).(Cv,dABdx);
end

"Overload of batch_inv! for Dual numbers"
function batch_inv!(X::CuArray{ForwardDiff.Dual{T,V,N},3}, A::CuArray{ForwardDiff.Dual{T,V,N},3}) where {T,V,N}
    #@show typeof(ForwardDiff.value.(A))
    #@show T,V,N
    Atemp = ForwardDiff.value.(A)
    invA  = 0 * Atemp;
    
    # Set invA=A⁻¹
    batch_inv!(invA,Atemp)

    # Find sparsity (brute force)
    doIt = zeros(Bool,N)
    K    = [ForwardDiff.partials.(A,i) for i=1:N]
    doIt = [~all(iszero.(K[i])) for i=1:N]
    #@show doIt
    #dummy = 0*similar(K[1])

    # Compute derivatives ∂A⁻¹/∂x = -A⁻¹ * ∂A/∂x * A⁻¹; using NNlib batched matrix multiply
    @timeit "InvDerivs" dAdx = [doIt[i] ? -invA ⊠ K[i] ⊠ invA : K[i] for i=1:N];
    # Pack into tuples again
    dAdx = ForwardDiff.Partials.(tuple.(dAdx...));
    X .= eltype(X).(invA,dAdx);
end