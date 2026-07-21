-- Kingdom Hearts Final Mix (Steam)
-- Combined Sora combo/visual controller v9 proof of concept.
--
-- REQUIRED MSET
--   xa_ex_0010_SoraComboVisuals_v9_POC.mset
--   SHA-256: 674e9588b0959bcfadc986cb394c7d9e5d0f3c937ec93cb8659c1371ce1cd2ea
--
-- LAYOUT
--   C8 ground attack 1: Raid throw -> real second press -> Raid catch
--   C9 ground attack 2: Raid throw -> real second press -> Raid catch
--   D0 Sliding Dash: Judgement Raid -> real second press -> Raid catch
--   CC air attack 1: Aerial Sweep -> real second press -> Ragnarok F7
--   CD air attack 2: Aerial Sweep -> real second press -> Ragnarok F7
--   D4 Guard: Ripple Drive visual with Guard's native non-damaging control
--   DC Dodge Roll: Zantetsuken visual with Dodge Roll's native non-damaging control
--
-- No input is generated. This script never writes animation ID, resolved
-- motion index, animation time, damage, hitbox, movement, HP, or speed.
-- It temporarily redirects only active motion-pointer entries so a real
-- second Attack press selects the requested finisher visual.
--
-- IMPORTANT DEFENSE NOTE
--   The MSET retains Guard/Dodge Roll's original non-damaging control tails.
--   This POC does not yet force an undocumented invulnerability flag. Test
--   whether the native D4/DC defensive states remain active for the longer
--   100-frame replacement visuals before any separate invulnerability write
--   is added.

-- ========================================================================
-- EDITABLE SETTINGS
-- ========================================================================

local ENABLE_CONTROLLER = true
local LOG_DETAILS = true

-- ========================================================================
-- VERIFIED STEAM ADDRESSES AND V9 LAYOUT
-- ========================================================================

local SORA_POINTER = 0x2537E48
local POINTER_BANK_TABLE = 0x2EE3980

local CURRENT_ANIMATION_OFFSET = 0x164
local RESOLVED_INDEX_OFFSET = 0x168
local ANIMATION_TIME_OFFSET = 0x16C
local ACTIVE_POINTER_ARRAY_OFFSET = 0x1D4

local ID_C8 = 0xC8
local ID_C9 = 0xC9
local ID_CA = 0xCA
local ID_CB = 0xCB
local ID_CC = 0xCC
local ID_CD = 0xCD
local ID_CE = 0xCE
local ID_D0 = 0xD0

local SLOT_C8 = 0x0062
local SLOT_C9 = 0x0063
local SLOT_CA = 0x0064
local SLOT_CB = 0x0065
local SLOT_CC = 0x0066
local SLOT_CD = 0x0067
local SLOT_CE = 0x0068
local SLOT_D0 = 0x006A
local SLOT_D4 = 0x006E
local SLOT_DC = 0x0075

-- Physical-record offsets relative to the canonical, never-patched slot 0x65
-- in xa_ex_0010_SoraComboVisuals_v9_POC.mset.
local SLOT_DELTA_FROM_65 = {
    [SLOT_C8] = -0x13FA0,
    [SLOT_C9] = -0xE860,
    [SLOT_CA] = -0x7E90,
    [SLOT_CB] = 0x0000,
    [SLOT_CC] = 0x5D80,
    [SLOT_CD] = 0xAE90,
    [SLOT_CE] = 0x11D60,
    [SLOT_D0] = 0x206A0,
    [SLOT_D4] = 0x3DD40,
    [SLOT_DC] = 0x70C00,
}

local EXPECTED_FRAMES = {
    [SLOT_C8] = 42,
    [SLOT_C9] = 42,
    [SLOT_CB] = 64,
    [SLOT_CC] = 56,
    [SLOT_CD] = 56,
    [SLOT_CE] = 80,
    [SLOT_D0] = 76,
    [SLOT_D4] = 100,
    [SLOT_DC] = 100,
}

local ENTRIES = {
    {
        name = "C8 ground attack 1",
        id = ID_C8,
        slot = SLOT_C8,
        firstVisual = "Raid throw",
        secondVisual = "Raid catch",
        replacementSlot = SLOT_CB,
        patchSlots = { SLOT_C9 },
        catches = {
            { id = ID_C9, slot = SLOT_C9 },
        },
    },
    {
        name = "C9 ground attack 2",
        id = ID_C9,
        slot = SLOT_C9,
        firstVisual = "Raid throw",
        secondVisual = "Raid catch",
        replacementSlot = SLOT_CB,
        patchSlots = {},
        catches = {
            { id = ID_CB, slot = SLOT_CB },
        },
    },
    {
        name = "D0 Sliding Dash",
        id = ID_D0,
        slot = SLOT_D0,
        firstVisual = "Judgement Raid",
        secondVisual = "Raid catch",
        replacementSlot = SLOT_CB,
        -- Sliding Dash's native combo position can select a different ground
        -- follow-up. Route every possible ground continuation to the catch.
        patchSlots = { SLOT_C8, SLOT_C9, SLOT_CA },
        catches = {
            { id = ID_C8, slot = SLOT_C8 },
            { id = ID_C9, slot = SLOT_C9 },
            { id = ID_CA, slot = SLOT_CA },
            { id = ID_CB, slot = SLOT_CB },
        },
    },
    {
        name = "CC air attack 1",
        id = ID_CC,
        slot = SLOT_CC,
        firstVisual = "Aerial Sweep",
        secondVisual = "Ragnarok F7",
        replacementSlot = SLOT_CE,
        patchSlots = { SLOT_CD },
        catches = {
            { id = ID_CD, slot = SLOT_CD },
        },
    },
    {
        name = "CD air attack 2",
        id = ID_CD,
        slot = SLOT_CD,
        firstVisual = "Aerial Sweep",
        secondVisual = "Ragnarok F7",
        replacementSlot = SLOT_CE,
        patchSlots = {},
        catches = {
            { id = ID_CE, slot = SLOT_CE },
        },
    },
}

-- ========================================================================
-- RUNTIME STATE
-- ========================================================================

local enabled = false
local disabledReason = nil
local previousSora = 0
local phase = "waiting"
local activeEntry = nil
local activePointerArray = 0
local sequenceNumber = 0
local appliedPatches = {}

local function log(message)
    ConsolePrint("[SoraComboVisualsV9] " .. message)
end

local function detail(message)
    if LOG_DETAILS then
        log(message)
    end
end

local function unsigned32(value)
    if value == nil then
        return 0
    end
    if value < 0 then
        return value + 4294967296
    end
    return value
end

local function resolveCompressedPointer(encoded)
    local value = unsigned32(encoded)
    if value == 0 then
        return 0
    end
    if value < 0x80000000 then
        return value
    end

    local payload = value - 0x80000000
    local bankIndex = math.floor(payload / 0x2000000)
    local bankOffset = payload % 0x2000000
    local bankBase = ReadLong(POINTER_BANK_TABLE + bankIndex * 8)
    if bankBase == nil or bankBase == 0 then
        return 0
    end
    return bankBase + bankOffset
end

local function addMotionOffset(encoded, delta)
    local value = unsigned32(encoded)
    if value == 0 then
        return 0
    end
    if value < 0x80000000 then
        local direct = value + delta
        if direct < 0 then
            return 0
        end
        return direct
    end

    local bankPrefix = value - (value % 0x2000000)
    local bankOffset = value % 0x2000000
    local newOffset = bankOffset + delta
    if newOffset < 0 or newOffset >= 0x2000000 then
        return 0
    end
    return bankPrefix + newOffset
end

local function readResolvedIndex(sora)
    return unsigned32(ReadInt(sora + RESOLVED_INDEX_OFFSET, true)) % 0x10000
end

local function getActivePointerArray(sora)
    local encoded = unsigned32(ReadInt(
        sora + ACTIVE_POINTER_ARRAY_OFFSET,
        true
    ))
    return resolveCompressedPointer(encoded), encoded
end

local function readMotionPointer(pointerArray, slot)
    if pointerArray == nil or pointerArray == 0 then
        return 0
    end
    return unsigned32(ReadInt(pointerArray + slot * 4, true))
end

local function writeMotionPointer(pointerArray, slot, encodedPointer)
    WriteInt(pointerArray + slot * 4, unsigned32(encodedPointer), true)
end

local function expectedPointersFromCatch(pointerArray)
    local canonical65 = readMotionPointer(pointerArray, SLOT_CB)
    if canonical65 == 0 then
        return nil, "canonical slot 0x65 pointer was zero"
    end

    local expected = {}
    for slot, delta in pairs(SLOT_DELTA_FROM_65) do
        local pointer = addMotionOffset(canonical65, delta)
        if pointer == 0 then
            return nil, string.format(
                "slot 0x%02X delta crossed a pointer bank",
                slot
            )
        end
        expected[slot] = pointer
    end
    return expected, nil
end

local function validateFrameCount(encodedPointer, expectedFrames)
    local actual = resolveCompressedPointer(encodedPointer)
    if actual == 0 then
        return false, "motion pointer could not be resolved"
    end
    local frames = unsigned32(ReadInt(actual + 4, true))
    if frames ~= expectedFrames then
        return false, string.format(
            "expected %d frames but found %d",
            expectedFrames,
            frames
        )
    end
    return true, nil
end

local function inspectV9Layout(sora, allowTemporaryRoutes)
    local pointerArray, encodedArray = getActivePointerArray(sora)
    if pointerArray == 0 then
        return nil, "active motion-pointer array could not be resolved"
    end

    local expected, expectedError = expectedPointersFromCatch(pointerArray)
    if expected == nil then
        return nil, expectedError
    end

    local pointer65 = expected[SLOT_CB]
    local pointer68 = expected[SLOT_CE]
    for slot, expectedPointer in pairs(expected) do
        local current = readMotionPointer(pointerArray, slot)
        local temporarilyValid = allowTemporaryRoutes
            and ((slot == SLOT_C8 or slot == SLOT_C9 or slot == SLOT_CA)
                and current == pointer65
                or (slot == SLOT_CD and current == pointer68))

        if current ~= expectedPointer and not temporarilyValid then
            return nil, string.format(
                "active MSET does not match v9 at slot 0x%02X "
                    .. "(found 0x%08X expected 0x%08X)",
                slot,
                current,
                expectedPointer
            )
        end
    end

    for slot, expectedFrames in pairs(EXPECTED_FRAMES) do
        local ok, frameError = validateFrameCount(expected[slot], expectedFrames)
        if not ok then
            return nil, string.format(
                "slot 0x%02X frame validation failed: %s",
                slot,
                frameError
            )
        end
    end

    return {
        pointerArray = pointerArray,
        encodedArray = encodedArray,
        expected = expected,
    }, nil
end

local function restorePatches(reason)
    local success = true
    local failure = nil

    for index = #appliedPatches, 1, -1 do
        local patch = appliedPatches[index]
        local current = readMotionPointer(activePointerArray, patch.slot)
        if current == patch.replacement then
            writeMotionPointer(activePointerArray, patch.slot, patch.original)
            current = readMotionPointer(activePointerArray, patch.slot)
        end
        if current ~= patch.original then
            success = false
            failure = string.format(
                "slot 0x%02X restore conflict: found 0x%08X",
                patch.slot,
                current
            )
            break
        end
    end

    if success and #appliedPatches > 0 then
        detail("Restored temporary motion routes (" .. tostring(reason) .. ").")
    end
    appliedPatches = {}
    return success, failure
end

local function clearSequence()
    phase = "waiting"
    activeEntry = nil
    activePointerArray = 0
    appliedPatches = {}
end

local function resetSequence(reason)
    local restored, restoreError = restorePatches(reason)
    clearSequence()
    if not restored then
        enabled = false
        disabledReason = restoreError
        log("DISABLED: " .. restoreError)
        return false
    end
    return true
end

local function cleanStaleRoutes(sora)
    local layout, layoutError = inspectV9Layout(sora, true)
    if layout == nil then
        return false, layoutError
    end

    local pointer65 = layout.expected[SLOT_CB]
    local pointer68 = layout.expected[SLOT_CE]
    local cleaned = false

    for _, slot in ipairs({ SLOT_C8, SLOT_C9, SLOT_CA }) do
        local current = readMotionPointer(layout.pointerArray, slot)
        if current == pointer65 and current ~= layout.expected[slot] then
            writeMotionPointer(layout.pointerArray, slot, layout.expected[slot])
            cleaned = true
        end
    end

    local current67 = readMotionPointer(layout.pointerArray, SLOT_CD)
    if current67 == pointer68 and current67 ~= layout.expected[SLOT_CD] then
        writeMotionPointer(
            layout.pointerArray,
            SLOT_CD,
            layout.expected[SLOT_CD]
        )
        cleaned = true
    end

    local cleanLayout, cleanError = inspectV9Layout(sora, false)
    if cleanLayout == nil then
        return false, cleanError
    end
    if cleaned then
        detail("Recovered and restored stale routes from a prior script reload.")
    end
    return true, nil
end

local function applyEntryPatches(entry, layout)
    local replacement = layout.expected[entry.replacementSlot]
    for _, slot in ipairs(entry.patchSlots) do
        local current = readMotionPointer(layout.pointerArray, slot)
        local expected = layout.expected[slot]
        if current ~= expected then
            return false, string.format(
                "slot 0x%02X changed before routing (0x%08X)",
                slot,
                current
            )
        end

        writeMotionPointer(layout.pointerArray, slot, replacement)
        local readback = readMotionPointer(layout.pointerArray, slot)
        if readback ~= replacement then
            return false, string.format(
                "slot 0x%02X route failed readback (0x%08X)",
                slot,
                readback
            )
        end

        appliedPatches[#appliedPatches + 1] = {
            slot = slot,
            original = expected,
            replacement = replacement,
        }
    end
    return true, nil
end

local function beginEntry(entry, sora, animationFrame)
    local layout, layoutError = inspectV9Layout(sora, false)
    if layout == nil then
        enabled = false
        disabledReason = layoutError
        log("DISABLED: " .. layoutError)
        return false
    end

    phase = "first"
    activeEntry = entry
    activePointerArray = layout.pointerArray
    appliedPatches = {}
    sequenceNumber = sequenceNumber + 1

    local patched, patchError = applyEntryPatches(entry, layout)
    if not patched then
        local previousNumber = sequenceNumber
        resetSequence("route setup failed")
        enabled = false
        disabledReason = patchError
        log(string.format(
            "SEQUENCE #%d DISABLED during route setup: %s",
            previousNumber,
            patchError
        ))
        return false
    end

    log(string.format(
        "SEQUENCE #%d START: %s uses %s at frame %.1f; "
            .. "a real second Attack press selects %s.",
        sequenceNumber,
        entry.name,
        entry.firstVisual,
        animationFrame,
        entry.secondVisual
    ))
    return true
end

local function catchHasStarted(entry, animation, slot)
    for _, candidate in ipairs(entry.catches) do
        if animation == candidate.id and slot == candidate.slot then
            return true
        end
    end
    return false
end

local function verifyActivePatches()
    for _, patch in ipairs(appliedPatches) do
        local current = readMotionPointer(activePointerArray, patch.slot)
        if current ~= patch.replacement then
            return false, string.format(
                "slot 0x%02X route changed to 0x%08X",
                patch.slot,
                current
            )
        end
    end
    return true, nil
end

local function findEntry(animation, slot)
    for _, entry in ipairs(ENTRIES) do
        if animation == entry.id and slot == entry.slot then
            return entry
        end
    end
    return nil
end

local function frameLogic()
    local sora = ReadLong(SORA_POINTER)
    if sora == nil or sora == 0 then
        if previousSora ~= 0 then
            resetSequence("Sora pointer unavailable")
        end
        previousSora = 0
        return
    end

    if previousSora ~= 0 and sora ~= previousSora then
        if not resetSequence("Sora pointer changed") then
            return
        end
    end
    previousSora = sora

    local animation = ReadByte(sora + CURRENT_ANIMATION_OFFSET, true)
    local slot = readResolvedIndex(sora)
    local animationFrame = ReadFloat(sora + ANIMATION_TIME_OFFSET, true)

    if phase == "waiting" then
        local entry = findEntry(animation, slot)
        if entry ~= nil then
            beginEntry(entry, sora, animationFrame)
        end
        return
    end

    local currentArray = getActivePointerArray(sora)
    if currentArray ~= activePointerArray then
        local number = sequenceNumber
        resetSequence("active pointer array changed")
        detail(string.format(
            "SEQUENCE #%d aborted because the active motion bank changed.",
            number
        ))
        return
    end

    local patchesValid, patchError = verifyActivePatches()
    if not patchesValid then
        enabled = false
        disabledReason = patchError
        log("DISABLED: " .. patchError)
        resetSequence("pointer route conflict")
        return
    end

    if phase == "first" then
        if catchHasStarted(activeEntry, animation, slot) then
            phase = "second"
            log(string.format(
                "SEQUENCE #%d SECOND PRESS ACCEPTED: %s -> %s at frame %.1f.",
                sequenceNumber,
                activeEntry.firstVisual,
                activeEntry.secondVisual,
                animationFrame
            ))
            return
        end

        if animation ~= activeEntry.id or slot ~= activeEntry.slot then
            local number = sequenceNumber
            local name = activeEntry.name
            local restored = resetSequence("first animation exited without follow-up")
            if restored then
                detail(string.format(
                    "SEQUENCE #%d COMPLETE WITHOUT SECOND PRESS: %s exited.",
                    number,
                    name
                ))
            end
        end
        return
    end

    if phase == "second"
        and not catchHasStarted(activeEntry, animation, slot)
    then
        local number = sequenceNumber
        local name = activeEntry.name
        local restored = resetSequence("second animation exited")
        if restored then
            detail(string.format(
                "SEQUENCE #%d COMPLETE: %s returned to normal routing.",
                number,
                name
            ))
        end
    end
end

function _OnInit()
    SetHertz(60)
    enabled = ENABLE_CONTROLLER
    disabledReason = nil
    clearSequence()

    if not enabled then
        disabledReason = "ENABLE_CONTROLLER is false"
        log("DISABLED by setting.")
        return
    end

    local sora = ReadLong(SORA_POINTER)
    if sora ~= nil and sora ~= 0 then
        previousSora = sora
        local cleaned, cleanError = cleanStaleRoutes(sora)
        if not cleaned then
            -- Alternate banks used by limits/summons are legitimate. The
            -- exact v9 layout is checked again when a configured entry starts.
            detail("Initial v9 layout validation deferred: " .. cleanError)
        end
    else
        previousSora = 0
    end

    log("READY for the v9 POC MSET.")
    log("Ground C8/C9: Raid throw, real second press Raid catch.")
    log("Sliding Dash: Judgement Raid, real second press Raid catch.")
    log("Air CC/CD: Aerial Sweep, real second press Ragnarok F7.")
    log("Guard/Dodge use non-damaging native defensive control tails.")
    log("No automatic input or animation-ID/index/time writes are used.")
end

function _OnFrame()
    if not enabled then
        return
    end

    local ok, frameError = pcall(frameLogic)
    if not ok then
        pcall(resetSequence, "runtime error")
        enabled = false
        disabledReason = tostring(frameError)
        log("DISABLED after runtime error: " .. disabledReason)
    end
end
