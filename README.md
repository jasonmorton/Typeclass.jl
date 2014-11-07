Typeclass.jl
============

[![Build Status](https://travis-ci.org/jasonmorton/Typeclass.jl.svg?branch=master)](https://travis-ci.org/jasonmorton/Typeclass.jl)

Multiparameter typeclasses for Julia. Allows circular definitions, interfaces, and so on.

To use it, define a class by giving some methods, which can either have an output type or default implementation.  Here is an example with only output types:
```
@class Monoid T begin
       munit(::T)::T
       mappend(x::T,y::T)::T
end
```

Then declare some type to be an instance of the class, supplying any needed methods.  

```
@instance Monoid Array{Int} begin
       munit(::Array{Int})=Int[]
       mappend(x::Array{Int},y::Array{Int})=[x;y]
end
    
@test munit(Int[3])==Int[]
@test mappend([3,4],[4,5])==[3,4,4,5]
```

Circular definitions are fine.  They are resolved by Typeclass.jl once you give the instance declaration, and you only need to supply enough information to disambiguate (e.g. defining eq or noteq below is enough).
```
@class Eq T begin
    eq(x::T,y::T)=!noteq(x,y)
    noteq(x::T,y::T)=!eq(x,y)
    ==(x::T,y::T)=eq(x,y) # ignored unless use @instance! form
end
```

Note that  

    @instance

does NOT override any methods that are already able to operate on your type, while 

    @instance!

does register a new method.




More complex example: a monoidal category
```
@class MonoidalCategory Ob Mor begin
    dom(f::Mor)::Ob
    cod(f::Mor)::Ob
    id(A::Ob)::Mor
    compose(f::Mor,g::Mor)::Mor #f*g
    otimes(f::Mor,g::Mor)::Mor
    otimes(A::Ob,B::Ob)::Ob
    munit(::Ob)::Ob
    munit(f::Mor)=munit(dom(f))
    # syntax, using unicode
    ∘(f::Mor,g::Mor)=compose(f,g)
    ⊗(f::Mor,g::Mor)=otimes(f,g)
    ⊗(A::Ob,B::Ob)=otimes(A,B)
end
```

Now we can tell Julia how to treat matrices as a monoidal category.

```
typealias Mat Matrix{Float64}
@instance MonoidalCategory Int Mat begin
    dom(f::Mat)=size(f)[2]
    cod(f::Mat)=size(f)[1]
    id(A::Int)=eye(A)
    compose(f::Mat,g::Mat)=f*g
    otimes(f::Mat,g::Mat)=kron(f,g)
    otimes(A::Int,B::Int)=A*B
    munit(::Int)=1
end

@test id(2)⊗id(2) == id(4)
@test id(2)∘id(2) == id(2)
@test dom(rand(2,3))==3
```

