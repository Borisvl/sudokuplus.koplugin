local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local masks = require("core.masks")
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

-- Maximum number of nodes explored in one chain.
local MAX_DEPTH = 14

aic.MAX_DEPTH = MAX_DEPTH
aic.MAX_EXPANSIONS = 10000
aic.STATUS_SEARCH_CAPPED = "search_capped"

-- Bounds the worst-case BFS cost of a single AIC pass. A dense board with no
-- reachable elimination would otherwise explore every chain to full depth
-- (measured at multiple seconds per pass); the cap bounds one pass to ~10k
-- path expansions, which is far beyond what the real AIC examples need.
-- Divergence from rustoku: rustoku explores without bound. A capped pass
-- returns false without eliminations, so deep chains on pathological boards
-- are skipped (the puzzle then classifies as needing a guess).
local board_is_empty = board.raw_is_empty
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

local function chain_contains(chain, node)
    while chain do
        if chain.node == node then
            return true
        end
        chain = chain.parent
    end
    return false
end

local function is_weak_link(n1, n2)
    local r1, c1, v1 = decode(n1)
    local r2, c2, v2 = decode(n2)
    return v1 == v2 and units.sees(r1, c1, r2, c2)
end

local function zero_counts()
    return { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function build_link_counts(prop)
    local cell_counts = {}
    local row_counts = {}
    local col_counts = {}
    local box_counts = {}

    for i = 1, 9 do
        row_counts[i] = zero_counts()
        col_counts[i] = zero_counts()
        box_counts[i] = zero_counts()
    end

    for r = 0, 8 do
        cell_counts[r + 1] = {}
        for c = 0, 8 do
            local mask = cand_get(prop.candidates, r, c)
            cell_counts[r + 1][c + 1] = flags.count(mask)
            if board_is_empty(prop.board, r, c) then
                local box_idx = masks.get_box_idx(r, c)
                for v = 1, 9 do
                    local val_bit = bit.lshift(1, v - 1)
                    if bit.band(mask, val_bit) ~= 0 then
                        row_counts[r + 1][v] = row_counts[r + 1][v] + 1
                        col_counts[c + 1][v] = col_counts[c + 1][v] + 1
                        box_counts[box_idx + 1][v] = box_counts[box_idx + 1][v] + 1
                    end
                end
            end
        end
    end

    return {
        cell = cell_counts,
        row = row_counts,
        col = col_counts,
        box = box_counts,
    }
end

local function is_strong_link(n1, n2, counts)
    local r1, c1, v1 = decode(n1)
    local r2, c2, v2 = decode(n2)
    if r1 == r2 and c1 == c2 then
        return v1 ~= v2 and counts.cell[r1 + 1][c1 + 1] == 2
    end
    if v1 ~= v2 then
        return false
    end
    if r1 == r2 and counts.row[r1 + 1][v1] == 2 then
        return true
    end
    if c1 == c2 and counts.col[c1 + 1][v1] == 2 then
        return true
    end
    if masks.get_box_idx(r1, c1) == masks.get_box_idx(r2, c2) then
        local box_idx = masks.get_box_idx(r1, c1)
        return counts.box[box_idx + 1][v1] == 2
    end
    return false
end

local visit_counter = 0
local seen_visit = {}

local function find_next_nodes(prop, current, need_strong, counts, out_next_nodes)
    visit_counter = visit_counter + 1
    local v_id = visit_counter
    local count = 0

    local cr, cc, cv = decode(current)
    local mask = cand_get(prop.candidates, cr, cc)
    for v = 1, 9 do
        if v ~= cv and bit.band(mask, bit.lshift(1, v - 1)) ~= 0 then
            local nxt = encode(cr, cc, v)
            if not need_strong or is_strong_link(current, nxt, counts) then
                if seen_visit[nxt] ~= v_id then
                    seen_visit[nxt] = v_id
                    count = count + 1
                    out_next_nodes[count] = nxt
                end
            end
        end
    end
    local val_bit = bit.lshift(1, cv - 1)
    for c = 0, 8 do
        if c ~= cc and bit.band(cand_get(prop.candidates, cr, c), val_bit) ~= 0 then
            local nxt = encode(cr, c, cv)
            if not need_strong or is_strong_link(current, nxt, counts) then
                if seen_visit[nxt] ~= v_id then
                    seen_visit[nxt] = v_id
                    count = count + 1
                    out_next_nodes[count] = nxt
                end
            end
        end
    end
    for r = 0, 8 do
        if r ~= cr and bit.band(cand_get(prop.candidates, r, cc), val_bit) ~= 0 then
            local nxt = encode(r, cc, cv)
            if not need_strong or is_strong_link(current, nxt, counts) then
                if seen_visit[nxt] ~= v_id then
                    seen_visit[nxt] = v_id
                    count = count + 1
                    out_next_nodes[count] = nxt
                end
            end
        end
    end
    local box_idx = masks.get_box_idx(cr, cc)
    for _, cell in ipairs(units.box_cells(box_idx)) do
        local r, c = cell[1], cell[2]
        if (r ~= cr or c ~= cc) and bit.band(cand_get(prop.candidates, r, c), val_bit) ~= 0 then
            local nxt = encode(r, c, cv)
            if not need_strong or is_strong_link(current, nxt, counts) then
                if seen_visit[nxt] ~= v_id then
                    seen_visit[nxt] = v_id
                    count = count + 1
                    out_next_nodes[count] = nxt
                end
            end
        end
    end
    for i = count + 1, #out_next_nodes do
        out_next_nodes[i] = nil
    end
    return out_next_nodes
end

local function decode_chain(chain)
    local result = {}
    for index = chain.depth, 1, -1 do
        local r, c, v = decode(chain.node)
        result[index] = { r = r, c = c, val = v }
        chain = chain.parent
    end
    return result
end

local function find_eliminations(prop, path, chain)
    if chain.depth < 4 or chain.depth % 2 ~= 0 then
        return false
    end
    local start, last = chain.start, chain.node
    local sr, sc, sv = decode(start)
    local lr, lc, lv = decode(last)
    local progress = false
    if sv == lv then
        local val_bit = bit.lshift(1, sv - 1)
        local pattern
        for r = 0, 8 do
            for c = 0, 8 do
                if (r ~= sr or c ~= sc) and (r ~= lr or c ~= lc) then
                    local target = encode(r, c, sv)
                    if
                        bit.band(cand_get(prop.candidates, r, c), val_bit) ~= 0
                        and is_weak_link(start, target)
                        and is_weak_link(last, target)
                    then
                        pattern = pattern
                            or {
                                kind = "aic",
                                nodes = decode_chain(chain),
                                values = { sv },
                            }
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
                nodes = decode_chain(chain),
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
local function is_strong_linked(node, counts)
    local r, c, v = decode(node)
    if counts.cell[r + 1][c + 1] == 2 then
        return true
    end
    if counts.row[r + 1][v] == 2 then
        return true
    end
    if counts.col[c + 1][v] == 2 then
        return true
    end
    local box_idx = masks.get_box_idx(r, c)
    return counts.box[box_idx + 1][v] == 2
end

function aic.apply(prop, path)
    local max_depth = prop.aic_max_depth or aic.MAX_DEPTH
    local max_expansions = prop.aic_max_expansions or aic.MAX_EXPANSIONS
    local counts = build_link_counts(prop)
    local starts = {}
    for r = 0, 8 do
        for c = 0, 8 do
            local mask = cand_get(prop.candidates, r, c)
            for v = 1, 9 do
                if bit.band(mask, bit.lshift(1, v - 1)) ~= 0 then
                    local node = encode(r, c, v)
                    if is_strong_linked(node, counts) then
                        starts[#starts + 1] = node
                    end
                end
            end
        end
    end
    local expansions = 0
    local depth_capped = false
    local next_buf = {}
    for _, start in ipairs(starts) do
        local queue = {
            {
                node = start,
                start = start,
                parent = nil,
                depth = 1,
                last_link = "weak",
            },
        }
        local head = 1
        while head <= #queue do
            local current_path = queue[head]
            head = head + 1
            if current_path.depth >= max_depth then
                depth_capped = true
            else
                expansions = expansions + 1
                if expansions > max_expansions then
                    return false, aic.STATUS_SEARCH_CAPPED
                end
                local current = current_path.node
                local need_strong = current_path.last_link == "weak"
                for _, nxt in ipairs(find_next_nodes(prop, current, need_strong, counts, next_buf)) do
                    if not chain_contains(current_path, nxt) then
                        local new_path = {
                            node = nxt,
                            start = current_path.start,
                            parent = current_path,
                            depth = current_path.depth + 1,
                            last_link = need_strong and "strong" or "weak",
                        }
                        if new_path.last_link == "strong" and new_path.depth >= 4 then
                            if find_eliminations(prop, path, new_path) then
                                return true
                            end
                        end
                        queue[#queue + 1] = new_path
                    end
                end
            end
        end
    end
    if depth_capped then
        return false, aic.STATUS_SEARCH_CAPPED
    end
    return false
end

function aic.flags()
    return flags.ALTERNATING_INFERENCE_CHAIN
end

return aic
