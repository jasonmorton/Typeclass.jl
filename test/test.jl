include("../src/Typeclass.jl")
using Typeclass

@class Eq T begin
    eq(x::T,y::T)=!noteq(x,y)
    noteq(x::T,y::T)=!eq(x,y)
    ==(x::T,y::T)=eq(x,y)        #ignored unless use @instance! form
end

@instance Eq Int begin
    eq(x::Int,y::Int)=x==y
end

@assert noteq(3,4)

@instance Eq Float64 begin
    noteq(x::Float64,y::Float64)=x!=y
end

@assert eq(3.0,3.0)

#Note: if you write
#@instance Eq Int begin
#    eq(x,y)=x==y
#end
#stack overflow, as it should be

@class Semiring A begin
       plus(x::A,y::A)=x+y
       times(x::A,y::A)=x*y
end


type Foo
    f
end

@assert (Foo(3)==Foo(3) )==false

@instance Eq Foo begin
   eq(a::Foo, b::Foo) = a.f==b.f
end

@assert eq(Foo(3),Foo(3) )==true
@assert (Foo(3)==Foo(3) )==false

#test overwriting version
@instance! Eq Foo begin
   eq(a::Foo, b::Foo) = a.f==b.f
end
@assert (Foo(3)==Foo(3) )==true

@class NameEq T begin
    function eq(x::T,y::T)
        for name in names(x)
            if getfield(x,name)!=getfield(y,name)
                return false
            end
        end
        return true
    end
    ==(x::T,y::T)=eq(x::T,y::T)
    !=(x::T,y::T)=!eq(x::T,y::T)
end

type TestNameEq 
    field1
    field2
end


@assert (TestNameEq(3,4)==TestNameEq(3,4))==false
@instance NameEq TestNameEq
@assert (TestNameEq(3,4)==TestNameEq(3,4))==false
@assert eq(TestNameEq(3,4),TestNameEq(3,4))==true
@instance! NameEq TestNameEq
@assert (TestNameEq(3,4)==TestNameEq(3,4))==true



@class Monoid T begin
       munit(::T)::T
       mappend(x::T,y::T)::T
end

@instance Monoid Array{Int} begin
       munit(::Array{Int})=Int[]
       mappend(x::Array{Int},y::Array{Int})=[x;y]
end
    
@assert munit(Int[3])==Int[]
@assert mappend([3,4],[4,5])==[3,4,4,5]

    

#test multiple type parameters
@class Deq S T begin
    deq(x::S,y::T)=x==y
    dneq(x::S,y::T)= !deq(x,y)
end

@instance Deq Int Float64 begin
    deq(a::Int,b::Float64)=a==b
end

@assert dneq(3,4.0)
@assert deq(3,3.0)



#test function blocks in @instance
#test things in Base.show
import Base.show #o/w clobbers
@class Showable T begin
    function show(x::T,y::T)
        3==4
        print(x,y)
    end
end

#another circular definition with heavily overloaded operator
@class Addable T begin
    add(x::T,y::T)=x+y
    +(x::T,y::T)=add(x,y)
end
@instance Addable Int #avoids clobbering +, which would break Julia

#test function blocks in @instance
@instance Addable Foo begin
    function add(x::Foo,y::Foo)
        5==3
        try
            garble
        catch x
            print(x)
        end
        return Foo(x.f + y.f)
    end
end

@assert eq(Foo(4)+Foo(3),Foo(7))

type Addable1
    data::Int
end

type Addable2
    data::Int
end

@instance Addable Addable1 begin
    add(x::Addable1,y::Addable1)=x.data+y.data
end

@instance Addable Addable2 begin
    +(x::Addable2,y::Addable2)=x.data+y.data
end


#finally, the kind of stuff this was written to do

#typeclasses in a multiple dispatch language are properties of tuples of types
@class MonoidalCategory Ob Mor begin
    dom(f::Mor)::Ob
    cod(f::Mor)::Ob
    id(A::Ob)::Mor
    compose(f::Mor,g::Mor)::Mor #f*g
    otimes(f::Mor,g::Mor)::Mor
    otimes(A::Ob,B::Ob)::Ob
    munit(::Ob)::Ob
    munit(f::Mor)=munit(dom(f))
    #syntax, where % is used for otimes 
    *(f::Mor,g::Mor)=compose(f,g)
    |(f::Mor,g::Mor)=compose(g,f)
    %(f::Mor,g::Mor)=otimes(f,g)
    %(A::Ob,B::Ob)=otimes(A,B)
end


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
#Note: this won't overwrite *,|,% where they are defined.
@assert id(2)%id(2) == id(4)
@assert dom(rand(2,3))==3

