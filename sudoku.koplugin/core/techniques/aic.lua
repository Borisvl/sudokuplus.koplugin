local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

-- Alternating Inference Chain: a chain of alternating strong and weak links
-- between candidate nodes. If the first candidate is false, the chain forces
-- the last candidate true, so any candidate seeing both ends must be false.
-- Chains that start and end on the same value eliminate that value from the
-- mutual peers of the ends; chains closing on the same cell (discontinuous
-- nice loop) eliminate the other candidates of that cell.
--
-- Chain nodes are encoded as single integers ((r*9+c)*9+(v-1)) so the BFS
-- allocates no per-node tables; the pattern metadata decodes them back.
local aic = {}

local MAX_DEPTH = 14

-- Bounds the worst-case BFS cost of a single AIC pass. A dense board with no
-- reachable elimination would otherwise explore every chain to full depth
-- (measured at multiple seconds per pass); the cap bounds one pass to ~10k
-- path expansions, which is far beyond what the real AIC examples need.
-- Divergence from rustoku: rustoku explores without bound. A capped pass
-- returns false without eliminations, so deep chains on pathological boards
-- are skipped (the puzzle then classifies as needing a guess).
local MAX_EXPANSIONS = 10000

local board_is_empty = board.is_empty
local cand_get = candidates.get

local function encode(r, c, v)
    return (r * 9 + c) * 9 + (v - 1)
end

local function decode(node)
    local v = node % 9 + 1
    local rest = math.floor(node / 9)
    local c = rest % 9
    local r = math.floor(rest / 9)
    return r, c, v
end

local function chain_contains(nodes, node)
    for i = 1, #nodes do
        if nodes[i] == node then
            return true
        end
    end
    return false
end

local function is_weak_link(n1, n2)
    local r1, c1, v1 = decode(n1)
    local r2, c2, v2 = decode(n2)
    return v1 == v2 and units.sees(r1, c1, r2, c2)
end

local function unit_candidate_count(prop, cells, val_bit)
    local count = 0
    for _, cell in ipairs(cells) do
        local r, c = cell[1], cell[2]
        if board_is_empty(prop.board, r, c) and bit.band(cand_get(prop.candidates, r, c), val_bit) ~= 0 then
            count = count + 1
        end
    end
    return count
end

local function is_strong_link(prop, n1, n2)
    local r1, c1, v1 = decode(n1)
    local r2, c2, v2 = decode(n2)
    if r1 == r2 and c1 == c2 then
        return v1 ~= v2 and flags.count(cand_get(prop.candidates, r1, c1)) == 2
    end
    if v1 ~= v2 then
        return false
    end
    local val_bit = bit.lshift(1, v1 - 1)
    if r1 == r2 and unit_candidate_count(prop, units.row_cells(r1), val_bit) == 2 then
        return true
    end
    if c1 == c2 and unit_candidate_count(prop, units.col_cells(c1), val_bit) == 2 then
        return true
    end
    if math.floor(r1 / 3) == math.floor(r2 / 3) and math.floor(c1 / 3) == math.floor(c2 / 3) then
        return unit_candidate_count(prop, units.box_cells(math.floor(r1 / 3) * 3 + math.floor(c1 / 3)), val_bit) == 2
    end
    return false
end

local function find_next_nodes(prop, current, need_strong)
    local cr, cc, cv = decode(current)
    local next_nodes = {}
    local mask = cand_get(prop.candidates, cr, cc)
    for v = 1, 9 do
        if v ~= cv and bit.band(mask, bit.lshift(1, v - 1)) ~= 0 then
            local next = encode(cr, cc, v)
            if not need_strong or is_strong_link(prop, current, next) then
                next_nodes[#next_nodes + 1] = next
            end
        end
    end
    local val_bit = bit.lshift(1, cv - 1)
    for c = 0, 8 do
        if c ~= cc and bit.band(cand_get(prop.candidates, cr, c), val_bit) ~= 0 then
            local next = encode(cr, c, cv)
            if not need_strong or is_strong_link(prop, current, next) then
                next_nodes[#next_nodes + 1] = next
            end
        end
    end
    for r = 0, 8 do
        if r ~= cr and bit.band(cand_get(prop.candidates, r, cc), val_bit) ~= 0 then
            local next = encode(r, cc, cv)
            if not need_strong or is_strong_link(prop, current, next) then
                next_nodes[#next_nodes + 1] = next
            end
        end
    end
    local box_idx = math.floor(cr / 3) * 3 + math.floor(cc / 3)
    for _, cell in ipairs(units.box_cells(box_idx)) do
        local r, c = cell[1], cell[2]
        if (r ~= cr or c ~= cc) and bit.band(cand_get(prop.candidates, r, c), val_bit) ~= 0 then
            local next = encode(r, c, cv)
            if not need_strong or is_strong_link(prop, current, next) then
                next_nodes[#next_nodes + 1] = next
            end
        end
    end
    return next_nodes
end

local function decode_nodes(nodes)
    local result = {}
    for i = 1, #nodes do
        local r, c, v = decode(nodes[i])
        result[i] = { r = r, c = c, val = v }
    end
    return result
end

local function find_eliminations(prop, path, nodes)
    if #nodes < 4 or #nodes % 2 ~= 0 then
        return false
    end
    local start, last = nodes[1], nodes[#nodes]
    local sr, sc, sv = decode(start)
    local lr, lc, lv = decode(last)
    local progress = false
    if sv == lv then
        local val_bit = bit.lshift(1, sv - 1)
        local pattern = {
            kind = "aic",
            nodes = decode_nodes(nodes),
            values = { sv },
        }
        for r = 0, 8 do
            for c = 0, 8 do
                if (r ~= sr or c ~= sc) and (r ~= lr or c ~= lc) then
                    local target = encode(r, c, sv)
                    if
                        bit.band(cand_get(prop.candidates, r, c), val_bit) ~= 0
                        and is_weak_link(start, target)
                        and is_weak_link(last, target)
                    then
                        progress = prop:eliminate_candidate(r, c, val_bit, aic.flags(), path, pattern) or progress
                    end
                end
            end
        end
    elseif sr == lr and sc == lc then
        local mask = cand_get(prop.candidates, sr, sc)
        local keep = bit.bor(bit.lshift(1, sv - 1), bit.lshift(1, lv - 1))
        local remove = bit.band(mask, bit.bnot(keep))
        if remove ~= 0 then
            local pattern = {
                kind = "aic",
                nodes = decode_nodes(nodes),
                values = candidates.from_mask(remove),
            }
            progress = prop:eliminate_multiple_candidates(sr, sc, remove, aic.flags(), path, pattern)
        end
    end
    return progress
end

-- A chain's first outbound link is always strong, so a candidate that is not
-- part of any strong link can never start a valid chain. Filtering the BFS
-- starts this way prunes dense boards soundly (same result, far less work).
local function is_strong_linked(prop, node)
    local r, c, v = decode(node)
    if flags.count(cand_get(prop.candidates, r, c)) == 2 then
        return true
    end
    local val_bit = bit.lshift(1, v - 1)
    if unit_candidate_count(prop, units.row_cells(r), val_bit) == 2 then
        return true
    end
    if unit_candidate_count(prop, units.col_cells(c), val_bit) == 2 then
        return true
    end
    return unit_candidate_count(prop, units.box_cells(math.floor(r / 3) * 3 + math.floor(c / 3)), val_bit) == 2
end

function aic.apply(prop, path)
    local starts = {}
    for r = 0, 8 do
        for c = 0, 8 do
            local mask = cand_get(prop.candidates, r, c)
            for v = 1, 9 do
                if bit.band(mask, bit.lshift(1, v - 1)) ~= 0 then
                    local node = encode(r, c, v)
                    if is_strong_linked(prop, node) then
                        starts[#starts + 1] = node
                    end
                end
            end
        end
    end
    local expansions = 0
    for _, start in ipairs(starts) do
        local queue = { { nodes = { start }, last_link = "weak" } }
        local head = 1
        while head <= #queue do
            local current_path = queue[head]
            head = head + 1
            if #current_path.nodes < MAX_DEPTH then
                expansions = expansions + 1
                if expansions > MAX_EXPANSIONS then
                    return false
                end
                local current = current_path.nodes[#current_path.nodes]
                local need_strong = current_path.last_link == "weak"
                for _, next in ipairs(find_next_nodes(prop, current, need_strong)) do
                    if not chain_contains(current_path.nodes, next) then
                        local nodes = {}
                        for i = 1, #current_path.nodes do
                            nodes[i] = current_path.nodes[i]
                        end
                        nodes[#nodes + 1] = next
                        local new_path = {
                            nodes = nodes,
                            last_link = need_strong and "strong" or "weak",
                        }
                        if new_path.last_link == "strong" and #new_path.nodes >= 4 then
                            if find_eliminations(prop, path, new_path.nodes) then
                                return true
                            end
                        end
                        queue[#queue + 1] = new_path
                    end
                end
            end
        end
    end
    return false
end

function aic.flags()
    return flags.ALTERNATING_INFERENCE_CHAIN
end

return aic
