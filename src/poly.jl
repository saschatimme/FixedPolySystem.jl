"""
    Poly(p::AbstractPolynomial)
    Poly(exponents, coeffs, homogenized=false)

A structure for fast multivariate Polynomial evaluation.
Polynomials created from a TypedPolynomial a never assumed to be homogenized.

### Fields
* `exponents::Matrix{Int}`: Each column represents the exponent of a term. The columns are sorted lexicographically by total degree.
* `coeffs::Vector{T}`: List of the coefficients.
* `homogenized::Bool`: Indicates whether a polynomial was homogenized

### Example
```
Poly: 3XYZ^2 - 2X^3Y
exponents:
    [ 3 1
      1 1
      0 2 ]
coeffs: [-2.0, 3.0]
```
"""
struct Poly{T<:Number}
    exponents::Matrix{Int}
    coeffs::Vector{T}
    homogenized::Bool

    function Poly{T}(exponents::Matrix{Int}, coeffs::Vector{T}, homogenized::Bool) where {T<:Number}
        sorted_cols = sort!([1:size(exponents,2);], lt=((i, j) -> lt_total_degree(exponents[:,i], exponents[:,j])), rev=true)

        new(exponents[:, sorted_cols], coeffs[sorted_cols], homogenized)
    end
end
function Poly{T}(exponents::Matrix{Int}, coeffs::Vector{S}, homogenized::Bool) where {T<:Number, S<:Number}
    Poly{T}(exponents, convert(Vector{T}, coeffs), homogenized)
end
function Poly(exponents::Matrix{Int}, coeffs::Vector{T}, homogenized::Bool) where {T<:Number}
    Poly{T}(exponents, coeffs, homogenized)
end

function Poly(exponents::Matrix{Int}, coeffs::Vector{T}; homogenized=false) where {T<:Number}
    Poly{T}(exponents, coeffs, homogenized)
end
function Poly(exponents::Vector{Int}, coeffs::Vector{<:Number}; homogenized=false)
    Poly(reshape(exponents, (length(exponents), 1)), coeffs, homogenized)
end


function Poly(p::MP.AbstractPolynomial{T}, vars) where T
    exps, coeffs = coeffs_exponents(p, vars)
    Poly(exps, coeffs, false)
end

function Poly(p::MP.AbstractPolynomial{T}) where T
    exps, coeffs = coeffs_exponents(p, MP.variables(p))
    Poly(exps, coeffs, false)
end
Poly(p::MP.AbstractPolynomialLike, vars) = Poly(MP.polynomial(p), vars)
Poly(p::MP.AbstractPolynomialLike) = Poly(MP.polynomial(p))

function Poly{T}(p::MP.AbstractPolynomial, vars) where {T}
    exps, coeffs = coeffs_exponents(p, vars)
    Poly{T}(exps, coeffs, false)
end

function Poly{T}(p::MP.AbstractPolynomial) where T
    exps, coeffs = coeffs_exponents(p, MP.variables(p))
    Poly{T}(exps, coeffs, false)
end
Poly{T}(p::MP.AbstractPolynomialLike, vars) where T = Poly{T}(MP.polynomial(p), vars)
Poly{T}(p::MP.AbstractPolynomialLike) where T= Poly{T}(MP.polynomial(p))

coefftype(::Poly{T}) where T = T

function coeffs_exponents(poly::MP.AbstractPolynomial{T}, vars) where {T}
    terms = MP.terms(poly)
    nterms = length(terms)
    nvars = length(vars)
    exps = Matrix{Int}(nvars, nterms)
    coeffs = Vector{T}(nterms)
    for j = 1:nterms
        term = terms[j]
        coeffs[j] = MP.coefficient(term)
        for i = 1:nvars
            exps[i,j] = MP.degree(term, vars[i])
        end
    end
    exps, coeffs
end

==(p::Poly, q::Poly) = p.exponents == q.exponents && p.coeffs == q.coeffs

"Sorts two vectory by total degree"
function lt_total_degree(a::Vector{T}, b::Vector{T}) where {T<:Real}
    sum_a = sum(a)
    sum_b = sum(b)
    if sum_a < sum_b
        return true
    elseif sum_a > sum_b
        return false
    else
        for i in eachindex(a)
            if a[i] < b[i]
                return true
            elseif a[i] > b[i]
                return false
            end
        end
    end
    false
end

Base.eltype(p::Poly{T}) where {T} = T

"""
    exponents(p::Poly)

Returns the exponents matrix
"""
exponents(p::Poly) = p.exponents

"""
    coeffs(p::Poly)

Returns the coefficient vector
"""
coeffs(p::Poly) = p.coeffs

"""
    homogenized(p::Poly)

Checks whether `p` was homogenized.
"""
homogenized(p::Poly) = p.homogenized

"""
    nterms(p::Poly)

Returns the number of terms of p
"""
nterms(p::Poly) = size(exponents(p), 2)

"""
    nvars(p::Poly)

Returns the number of variables of p
"""
nvariables(p::Poly) = size(exponents(p), 1)

"""
    deg(p::Poly)

Returns the (total) degree of p
"""
deg(p::Poly) = sum(exponents(p)[:,1])


# ITERATOR
start(p::Poly) = (1, nterms(p))
function next(p::Poly, state::Tuple{Int,Int})
    (i, limit) = state
    newstate = (i + 1, limit)
    val = (coeffs(p)[i], exponents(p)[:,i])

    (val, newstate)
end
done(p::Poly, state) = state[1] > state[2]
length(p::Poly) = nterms(p)

"""
    evaluate(p::Poly, x::AbstractVector)

Evaluates `p` at `x`, i.e. p(x)
"""
function evaluate(p::Poly{S}, x::AbstractVector{T}) where {S<:Number, T<:Number}
    cfs = coeffs(p)
    exps = exponents(p)
    nvars, nterms = size(exps)
    res = zero(promote_type(S,T))
    for j = 1:nterms
        @inbounds term = p.coeffs[j]
        for i = 1:nvars
            k = exps[i, j]
            @inbounds term *= x[i]^k
        end
        res += term
    end
    res
end
(p::Poly)(x) = evaluate(p, x)


"""
    substitute(p::Poly, i, x)

Substitute in `p` for the variable with index `i` `x`.
"""
function substitute(p::Poly{S}, varindex, x::T) where {S<:Number, T<:Number}
    cfs = coeffs(p)
    exps = exponents(p)
    nvars, nterms = size(exps)

    new_coeffs = Vector{promote_type(S,T)}()
    new_exps = Vector{Vector{Int}}()

    for j = 1:nterms
        coeff = cfs[j]
        exp = Vector{Int}(nvars - 1)
        # first we calculate the new coefficient and remove the varindex-th row
        for i = 1:nvars
            if i == varindex
                coeff *= x^(exps[i, j])
            elseif i > varindex
                exp[i-1] = exps[i, j]
            else
                exp[i] = exps[i, j]
            end
        end
        # now we have to delete possible duplicates
        found_duplicate = false
        for k = 1:length(new_exps)
            if new_exps[k] == exp
                new_coeffs[k] += coeff
                found_duplicate = true
                break
            end
        end
        if !found_duplicate
            push!(new_coeffs, coeff)
            push!(new_exps, exp)
        end
    end

    # now we have to create a new matrix and return the poly
    Poly(hcat(new_exps...), new_coeffs, p.homogenized)
end

"""
    differentiate(p::Poly, varindex)

Differentiates p w.r.t to the `varindex`th variable.
"""
function differentiate(p::Poly{T}, i_var) where T
    exps = copy(exponents(p))
    cfs = copy(coeffs(p))
    n_vars, n_terms = size(exps)

    zerocolumns = Int[]
    for j=1:n_terms
        k = exps[i_var, j]
        if k > 0
            exps[i_var, j] = max(0, k - 1)
            cfs[j] *= k
        else
            push!(zerocolumns , j)
        end
    end

    # now we have to get rid of all zeros
    nzeros = length(zerocolumns)
    if nzeros == 0
        return Poly(exps, cfs, p.homogenized)
    end

    skipped_cols = 0
    new_exps = zeros(Int, n_vars, n_terms - nzeros)
    new_coeffs = zeros(T, n_terms - nzeros)

    for j = 1:n_terms
        # if we not yet have skipped all zero columns
        if skipped_cols < nzeros && j == zerocolumns[skipped_cols+1]
            skipped_cols += 1
            continue
        end

        new_exps[:, j - skipped_cols] = exps[:, j]
        new_coeffs[j - skipped_cols] = cfs[j]
    end

    Poly(new_exps, new_coeffs, p.homogenized)
end


"""
    differentiate(p::Poly)

Differentiates Poly `p`. Returns the gradient vector.
"""
differentiate(poly::Poly) = map(i -> differentiate(poly, i), 1:nvariables(poly))

"""
    ∇(p::Poly)

Returns the gradient vector of `p`.
"""
@inline ∇(poly::Poly) = differentiate(poly)

"""
    ishomogenous(p::Poly)

Checks whether `p` is homogenous.
"""
function ishomogenous(p::Poly)
    monomials_degree = sum(exponents(p), 1)
    max_deg = monomials_degree[1]
    all(x -> x == max_deg, monomials_degree)
end

"""
    homogenize(p::Poly)

Makes `p` homogenous.
"""
function homogenize(p::Poly)
    if (p.homogenized)
        p
    else
        monomials_degree = sum(exponents(p), 1)
        max_deg = monomials_degree[1]
        Poly([max_deg - monomials_degree; exponents(p)], coeffs(p), homogenized=true)
    end
end

"""
    dehomogenize(p::Poly)

dehomogenizes `p`
"""
dehomogenize(p::Poly) = Poly(exponents(p)[2:end,:], coeffs(p), false)

"""
    multinomial(k::Vector{Int})

Computes the multinomial coefficient (|k| \\over k)
"""
function multinomial(k::Vector{Int})
    s = 0
    result = 1
    @inbounds for i in k
        s += i
        result *= binomial(s, i)
    end
    result
end

"""
    weyldot(f , g)

Compute the Bombieri-Weyl dot product between `Poly`s `f` and `g`.
Assumes that `f` and `g` are homogenous. See [here](https://en.wikipedia.org/wiki/Bombieri_norm)
for more details.
"""
function weyldot(f::Poly,g::Poly)
    if (f === g)
        return sum(x -> abs2(x[1]) / multinomial(x[2]), f)
    end
    result = 0
    for (c_f, exp_f) in f
        normalizer = multinomial(exp_f)
        for (c_g, exp_g) in g
            if exp_f == exp_g
                result += (c_f * conj(c_g)) / normalizer
                break
            end
        end
    end
    result
end

"""
    weylnorm(f::Poly)

Compute the Bombieri-Weyl norm for `f`. Assumes that `f` is homogenous.
See [here](https://en.wikipedia.org/wiki/Bombieri_norm) for more details.
"""
weylnorm(f::Poly) = √weyldot(f,f)
