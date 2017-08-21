module FixedPolySystem
    import MultivariatePolynomials
    const MP = MultivariatePolynomials
    import Base: start, next, done, length, eltype, show, ==, convert, promote_rule

    abstract type AbstractPolySystem{T} end

    include("poly.jl")
    include("system.jl")
    include("show.jl")
    include("convert_promote.jl")

    export Poly, PolySystem,
        nvariables, variables, polynomials, degrees,
        evaluate, evaluate!, differentiate,
        ishomogenous, homogenize, homogenized, dehomogenize,
        weyldot, weylnorm

end
