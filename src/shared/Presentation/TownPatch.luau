--!strict
--!native
-- Sparse, reversible RGBA XOR runs. Lighting changes reuse the original pixel/image storage.
local TownPatch = {}
function TownPatch.validate(patch: buffer, pixels: buffer)
	local at, last = 0, 0
	while at < buffer.len(patch) do
		assert(at + 8 <= buffer.len(patch), "truncated town patch header")
		local offset, count = buffer.readu32(patch, at), buffer.readu32(patch, at + 4)
		assert(count > 0 and offset >= last and offset + count <= buffer.len(pixels) / 4, "invalid town patch run")
		at += 8 + count * 4
		assert(at <= buffer.len(patch), "truncated town patch pixels")
		last = offset + count
	end
end
function TownPatch.apply(pixels: buffer, patch: buffer)
	-- Validate the whole input before mutating any pixels (safe fallback on corrupt local assets).
	TownPatch.validate(patch, pixels)
	local at = 0
	while at < buffer.len(patch) do
		local offset, count = buffer.readu32(patch, at) * 4, buffer.readu32(patch, at + 4)
		at += 8
		for i = 0, count - 1 do
			local target, source = offset + i * 4, at + i * 4
			buffer.writeu32(pixels, target, bit32.bxor(buffer.readu32(pixels, target), buffer.readu32(patch, source)))
		end
		at += count * 4
	end
end
return TownPatch
