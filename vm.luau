-- Register VM prototype. Input is assembly, not Luau source.
local VM = {}
local names = {'CONST','MOVE','ADD','SUB','MUL','DIV','MOD','POW','NEG','NOT','EQ','LT','LE','CONCAT','NEWTABLE','GETTABLE','SETTABLE','JMP','JFALSE','CALL','RETURN'}
function VM.compile(assembly, constants, seed)
    -- Private deterministic PRNG; does not change the user's random stream.
    local state = bit32.bxor(seed or math.random(1, 2147483647), 0x9e3779b9)
    if state == 0 then state = 1 end
    local function random(n)
        state = bit32.bxor(state, bit32.lshift(state,13))
        state = bit32.bxor(state, bit32.rshift(state,17))
        state = bit32.bxor(state, bit32.lshift(state,5))
        return state % n + 1
    end
    local ids = table.create(65535)
    for i=1,65535 do ids[i]=i end
    for i=65535,2,-1 do local j=random(i); ids[i],ids[j]=ids[j],ids[i] end
    local isa, reverse = {}, {}
    for i,name in names do isa[name]=ids[i]; reverse[ids[i]]=name end
    local code = table.create(#assembly)
    for i,ins in assembly do
        assert(isa[ins[1]], 'Unknown opcode at '..i)
        code[i]={isa[ins[1]],ins[2],ins[3],ins[4]}
    end
    return {code=code, constants=table.clone(constants or {}), isa=isa, reverse=reverse}
end
function VM.run(program, environment, budget)
    local r, pc, steps = {}, 1, 0
    local k = program.constants
    local handlers = {}
    local function op(name, fn) handlers[program.isa[name]]=fn end
    op('CONST',function(a,b) r[a]=k[b] end)
    op('MOVE',function(a,b) r[a]=r[b] end)
    op('ADD',function(a,b,c) r[a]=r[b]+r[c] end)
    op('SUB',function(a,b,c) r[a]=r[b]-r[c] end)
    op('MUL',function(a,b,c) r[a]=r[b]*r[c] end)
    op('DIV',function(a,b,c) r[a]=r[b]/r[c] end)
    op('MOD',function(a,b,c) r[a]=r[b]%r[c] end)
    op('POW',function(a,b,c) r[a]=r[b]^r[c] end)
    op('NEG',function(a,b) r[a]=-r[b] end)
    op('NOT',function(a,b) r[a]=not r[b] end)
    op('EQ',function(a,b,c) r[a]=r[b]==r[c] end)
    op('LT',function(a,b,c) r[a]=r[b]<r[c] end)
    op('LE',function(a,b,c) r[a]=r[b]<=r[c] end)
    op('CONCAT',function(a,b,c) r[a]=r[b]..r[c] end)
    op('NEWTABLE',function(a) r[a]={} end)
    op('GETTABLE',function(a,b,c) r[a]=r[b][r[c]] end)
    op('SETTABLE',function(a,b,c) r[a][r[b]]=r[c] end)
    op('JMP',function(a) pc=a end)
    op('JFALSE',function(a,b) if not r[a] then pc=b end end)
    -- CALL destination, environment-name constant, argument register.
    op('CALL',function(a,b,c) r[a]=assert(environment[k[b]],'Missing host function')(r[c]) end)
    local limit = budget or 10000000
    while true do
        steps += 1
        assert(steps<=limit, 'Instruction budget exceeded')
        local ins=assert(program.code[pc], 'Invalid program counter '..tostring(pc))
        pc += 1
        if ins[1]==program.isa.RETURN then return r[ins[2]], steps end
        assert(handlers[ins[1]],'Invalid opcode')(ins[2],ins[3],ins[4])
    end
end
return VM
