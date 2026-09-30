if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Spacer.lua
-- Spacer block factory.

local ADDON_NAME, ns = ...
local K = ns.BlockKit

local InstKey = K.InstKey

-------------------------------------------------------------------------------
--  SPACER (transparent block; the slot's optional bg tint still applies)
-------------------------------------------------------------------------------
ns.BlockFactories.spacer = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    function inst:Refresh() end
    function inst:Enable() end
    function inst:Disable() end
    function inst:Destroy() self._dead = true end
    function inst:GetAutoLength() return 0 end
    return inst
end
