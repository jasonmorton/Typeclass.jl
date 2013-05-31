module Typeclass
export @class, @instance, Typeclass_stub, Class

#for clarity
import Base.Meta.quot
isSymbol(x::Symbol)=true
isSymbol(x)=false
isQuote(x::Expr)=x.head==:quote
isQuote(x)=false
isDoubleColon(x::Expr)=x.head==:(::)
isDoubleColon(x)=false
isCall(x::Expr)=x.head==:call
isCall(x)=false
isFunction(x::Expr)=x.head==:function
isFunction(x)=false
isCurly(x::Expr)=x.head==:curly
isCurly(x)=false
isAssign(x::Expr)=x.head==:(=)
isAssign(x)=false


function parse_sig(call_expr)
    if call_expr.head != :call
        error("Expected call expression: $call_expr")
    else
        sym=call_expr.args[1]

        typesig={}
        for typex in call_expr.args[2:]
            if isDoubleColon(typex)
                #parse correctly for foo(::bar) and untyped
                s=length(typex.args)==2 ? typex.args[2] : typex.args[1]
                push!(typesig,s)
            else
                push!(typesig,:Any)
            end
        end
        (sym,typesig)
    end
end

#hack, but the supplied return values are not used right now, so not really important
unblock(b::Expr) = b.head==:block && length(b.args)==2 && b.args[1].head==:line? b.args[2] :error("Unblock is blocked")

function parse_declaration(dec::Expr)
    if isCall(dec) #foo(x::Int,y)
        return_type = Any
        call_expr = dec
        default_impl = nothing
    elseif isDoubleColon(dec) #foo(x::Int,y)::Int
        return_type = dec.args[2]
        call_expr = dec.args[1]
        default_impl = nothing
    #foo(x::Int,y) = (x+y) [::Int]
    elseif isAssign(dec)
        call_expr = dec.args[1]
        RHS = unblock(dec.args[2]) #was mishandling blocks, which are generally generated.
        if isDoubleColon(RHS) #foo(x::Int,y) = (x+y)::Int
            return_type = RHS.args[2]
            default_impl = RHS.args[1]
        else #foo(x::Int,y) = (x+y)
            return_type = Any
            default_impl = RHS
        end
    elseif isFunction(dec) #currently ignores return type info
        call_expr = dec.args[1]
        RHS = dec.args[2]
        return_type = Any
        default_impl = RHS
    else
        error("Unsupported function declaration $(dec), head must be :(::), :(=), :call, or :function")
    end
    call_expr,return_type,default_impl
end

immutable Typeclass_stub{T} end

function _class_code(args...)
    declarations=filter!(x->x.head!=:line,args[end].args)
    class_name=args[1]
    type_parameters=args[2:end-1]
    parsed_declarations = map(parse_declaration,declarations)
    class_decl=Expr(:(=),class_name,Class(class_name,type_parameters,parsed_declarations)) #was final line
    
    #stubs provide reflection info and prevent problems with derefing later
    funsyms = [ce.args[1] for (ce,j,k) in parsed_declarations]
    stub_block=Expr(:block)
    for sym in funsyms
        stub_decl=Expr(:(=),Expr(:call,sym,Expr(:(::),Expr(:curly,:Typeclass_stub,quot(class_name)))),true)
        push!(stub_block.args,stub_decl)
    end
    Expr(:block,class_decl,stub_block)
end

type Class
    class_name::Symbol
    type_parameters #symbols or curlies
    declarations #triple call_expr,return_type, default_implementation
end

import Base.show
function show(io::IO,C::Class)
    println(io,"Typeclass ",C.class_name)
    println(io,"Type parameters ",C.type_parameters)
    println(io,"Declarations ",C.declarations)
end

macro class(args...)
    esc(_class_code(args...))
end

typesub(binding,s::Symbol) = haskey(binding,s)? binding[s] :s
typesub(binding,e::Expr)   = Expr(e.head,[typesub(binding,a) for a in e.args]...)
typesub(binding,x)         = x


function _instance_code(typeclass,implementing_type,args)
    instance_declarations = length(args)>2? filter!(x->x.head!=:line,args[end].args) : {} #allows bare "@instance Foo Bar" with no user declarations
    parsed_instance_declarations = map(parse_declaration,instance_declarations)
    instance_declared_sigs = [parse_sig(pid[1]) for pid in parsed_instance_declarations]
    class_name=args[1]
    implementing_type_name=args[2] 

    if length(args)>2
        bindings = Dict(typeclass.type_parameters,args[2:end-1])
        implementing_type_names=args[2:end-1] 
    else
        bindings = Dict(typeclass.type_parameters,args[2:end]) #end=2
        implementing_type_names=args[2:end] 
    end

    instance_block=Expr(:block)   
    for d in instance_declarations
        push!(instance_block.args,d)     #run raw user declarations
    end

    class_block=Expr(:block)
    for parsed_dec in typeclass.declarations
        call_expr=parsed_dec[1]
        return_type=parsed_dec[2]
        default_impl=parsed_dec[3]

        LHS=typesub(bindings,call_expr)
        fsym,fsig=parse_sig(LHS)
        if !contains(instance_declared_sigs,parse_sig(LHS)) #if specialized, parsed_dec was not declared by user
            default_impl==nothing? error("Class method $LHS required by $class_name not implemented in instance declaration for $implementing_type_name") :nothing
            RHS=typesub(bindings,default_impl)
            decl=Expr(:(=),LHS,RHS)
            check=Expr(:call,isempty,Expr(:call,:methods,fsym,Expr(:tuple,fsig...))) #will error if fsym is undef, and try blocks cause hyg probs, hence stub
            warning=Expr(:call,:info,"Instance delcaration omitted method $(LHS) already defined, skipping specializing $class_name class method") 
            checked_decl = Expr(:if, check, decl, warning)
            push!(class_block.args,checked_decl)
        end
    end

    #allow adding Typeclass constraints to functions and types, as well as runtime checks
    registration_block=Expr(:block) #uses Graphs.jl method
    reg_LHS=Expr(:call,symbol(string("implements_",string(class_name))), [Expr(:(::),implementing_type_name) for implementing_type_name in implementing_type_names]...)
    push!(registration_block.args,Expr(:(=),reg_LHS,:true))

    Expr(:block,registration_block,instance_block,class_block)
end


macro instance(args...)
    typeclass=args[1]
    implementing_type=args[2]
    e=Expr(:call,_instance_code,typeclass,implementing_type,args) #stopping here just returns the code
    esc(Expr(:call,:eval,e)) #like calling eval( @instance ...) and stopping at previous line; added esc when made a module
end

macro ins(args...)
    global typeclass=args[1]
    println(typeclass)
    implementing_type=args[2]
    println(implementing_type)
    esc(Expr(:call,_instance_code,typeclass,implementing_type,args)) #stopping here just returns the code; added esc when made a module
end
#args=@id <decl>
#_instance_code(args[1],args[2],args) #to debug

end #module