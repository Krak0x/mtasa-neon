-- Generic, presentation-only mission trace. Mission code can publish status and
-- progress here, but this module exposes no path back into gameplay state.

TAGUP_TRACE = TAGUP_TRACE or {}

local DESIGN_WIDTH = 1920
local DESIGN_HEIGHT = 1080
local MAX_VISIBLE_STEPS = 5
local TOGGLE_KEY = "F7"
local CHATBOX_FONT_PATH = ":chatbox/fonts/Arial.ttf"

local palette = {
    panel = {3, 2, 1, 224},
    panelEdge = {218, 132, 30, 150},
    header = {10, 6, 2, 245},
    accent = {235, 145, 36, 255},
    accentSoft = {213, 116, 18, 58},
    text = {255, 239, 207, 255},
    textMuted = {202, 177, 139, 255},
    track = {123, 75, 24, 120},
    queued = {142, 121, 91, 255},
    failed = {244, 101, 101, 255},
    skipped = {210, 164, 76, 255},
}

local state = {
    visible = false,
    visibility = 0,
    steps = {},
    currentIndex = nil,
    title = "MISSION TRACE",
    subtitle = "AWAITING SEQUENCE",
    liveSequence = false,
    transitionTick = 0,
    lastFrameTick = getTickCount(),
}

local statusAliases = {
    active = "active",
    current = "active",
    running = "active",
    in_progress = "active",
    done = "done",
    complete = "done",
    completed = "done",
    passed = "done",
    queued = "queued",
    pending = "queued",
    future = "queued",
    failed = "failed",
    error = "failed",
    skipped = "skipped",
}

local fonts = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function createTraceFont(pixelSize, bold, fallback, fallbackScale)
    local screenWidth, screenHeight = guiGetScreenSize()
    -- Keep text readable on small displays independently from the panel's tighter
    -- layout scale. The font file is shared by the active chatbox resource.
    local fontScale = clamp(math.min(screenWidth / DESIGN_WIDTH, screenHeight / DESIGN_HEIGHT), 0.8, 1.4)
    local font = dxCreateFont(CHATBOX_FONT_PATH, math.floor(pixelSize * fontScale + 0.5), bold)
    if font then
        return {value = font, scale = 1}
    end
    outputDebugString(("[tagging-up-turf] Could not load chatbox font %s; using %s fallback"):format(CHATBOX_FONT_PATH, fallback), 2)
    return {value = fallback, scale = fallbackScale}
end

fonts.header = createTraceFont(22, true, "default-bold", 1.35)
fonts.title = createTraceFont(17, true, "default-bold", 1.15)
fonts.body = createTraceFont(14, false, "default", 1.05)
fonts.status = createTraceFont(12, true, "default-bold", 0.92)
fonts.footer = createTraceFont(12, false, "default", 0.9)

local function color(entry, opacity)
    return tocolor(entry[1], entry[2], entry[3], math.floor(entry[4] * clamp(opacity or 1, 0, 1) + 0.5))
end

local function easeOutCubic(value)
    local inverse = 1 - clamp(value, 0, 1)
    return 1 - inverse * inverse * inverse
end

local function normalizeStatus(status)
    if type(status) ~= "string" then
        return nil
    end
    return statusAliases[string.lower(status)]
end

local function normalizeProgress(progress)
    if type(progress) ~= "number" or progress ~= progress then
        return nil
    end
    if progress > 1 and progress <= 100 then
        progress = progress / 100
    end
    return clamp(progress, 0, 1)
end

local function resolveStep(reference)
    if type(reference) == "number" and reference >= 1 and reference <= #state.steps and reference % 1 == 0 then
        return reference
    end
    for index, step in ipairs(state.steps) do
        if step.id == reference or tostring(step.id) == tostring(reference) then
            return index
        end
    end
    return nil
end

local function setTransition()
    state.transitionTick = getTickCount()
end

local function deriveSequenceStatuses(currentIndex)
    for index, step in ipairs(state.steps) do
        if index < currentIndex then
            if step.status ~= "failed" and step.status ~= "skipped" then
                step.status = "done"
                step.progress = 1
            end
        elseif index == currentIndex then
            step.status = "active"
        elseif step.status ~= "failed" and step.status ~= "skipped" then
            step.status = "queued"
        end
    end
end

function TAGUP_TRACE.setSequence(sequence, options)
    if type(sequence) ~= "table" then
        return false
    end

    local steps = {}
    local initialCurrentIndex
    for index, source in ipairs(sequence) do
        local step
        if type(source) == "string" then
            step = {id = index, title = source}
        elseif type(source) == "table" and type(source.title or source.label or source.name) == "string" then
            step = {
                id = source.id or index,
                title = source.title or source.label or source.name,
                detail = source.detail or source.description,
                status = normalizeStatus(source.status),
                progress = normalizeProgress(source.progress),
            }
        else
            return false
        end

        step.status = step.status or "queued"
        step.progress = step.progress or (step.status == "done" and 1 or 0)
        if step.detail ~= nil then
            step.detail = tostring(step.detail)
        end
        if step.status == "active" and not initialCurrentIndex then
            initialCurrentIndex = index
        end
        step.displayProgress = step.progress
        step.changedTick = getTickCount()
        steps[#steps + 1] = step
    end

    options = type(options) == "table" and options or {}
    state.steps = steps
    state.currentIndex = initialCurrentIndex
    state.title = type(options.title) == "string" and options.title or "MISSION TRACE"
    state.subtitle = type(options.subtitle) == "string" and options.subtitle or "INSTRUCTION FEED"
    state.liveSequence = options.live == true
    setTransition()
    return true
end

function TAGUP_TRACE.setCurrent(reference, detail)
    local index = resolveStep(reference)
    if not index then
        return false
    end

    state.currentIndex = index
    deriveSequenceStatuses(index)
    if detail ~= nil then
        state.steps[index].detail = tostring(detail)
    end
    state.steps[index].changedTick = getTickCount()
    setTransition()
    return true
end

-- Debug stage skips must remain visually distinct from successful execution.
-- This advances the cursor while preserving completed history and marking only
-- the bypassed range as skipped.
function TAGUP_TRACE.skipTo(reference, detail)
    local index = resolveStep(reference)
    if not index or (state.currentIndex and index < state.currentIndex) then
        return false
    end

    local firstSkipped = state.currentIndex or 1
    for stepIndex = firstSkipped, index - 1 do
        local step = state.steps[stepIndex]
        if step.status ~= "done" and step.status ~= "failed" then
            step.status = "skipped"
        end
    end
    for stepIndex = index + 1, #state.steps do
        local step = state.steps[stepIndex]
        if step.status ~= "failed" and step.status ~= "skipped" then
            step.status = "queued"
        end
    end

    state.currentIndex = index
    state.steps[index].status = "active"
    if detail ~= nil then
        state.steps[index].detail = tostring(detail)
    end
    state.steps[index].changedTick = getTickCount()
    setTransition()
    return true
end

function TAGUP_TRACE.setStatus(reference, status, detail)
    local index = resolveStep(reference)
    local normalized = normalizeStatus(status)
    if not index or not normalized then
        return false
    end

    local step = state.steps[index]
    step.status = normalized
    if normalized == "done" then
        step.progress = 1
    elseif normalized == "active" then
        state.currentIndex = index
    end
    if detail ~= nil then
        step.detail = tostring(detail)
    end
    step.changedTick = getTickCount()
    setTransition()
    return true
end

-- A terminal failure cancels every still-pending operation. Keeping those rows as
-- queued would falsely suggest that a stopped mission is about to resume.
function TAGUP_TRACE.fail(reference, detail)
    local index = resolveStep(reference)
    if not index then
        return false
    end

    for stepIndex, step in ipairs(state.steps) do
        if stepIndex == index then
            step.status = "failed"
        elseif step.status == "active" or step.status == "queued" then
            step.status = "skipped"
        end
    end
    state.currentIndex = index
    if detail ~= nil then
        state.steps[index].detail = tostring(detail)
    end
    state.steps[index].changedTick = getTickCount()
    setTransition()
    return true
end

function TAGUP_TRACE.setProgress(reference, progress, detail)
    local index = resolveStep(reference)
    local normalized = normalizeProgress(progress)
    if not index or normalized == nil then
        return false
    end

    local step = state.steps[index]
    step.progress = normalized
    if detail ~= nil then
        step.detail = tostring(detail)
    end
    step.changedTick = getTickCount()
    return true
end

function TAGUP_TRACE.reset()
    state.steps = {}
    state.currentIndex = nil
    state.title = "MISSION TRACE"
    state.subtitle = "AWAITING SEQUENCE"
    state.liveSequence = false
    setTransition()
    return true
end

function TAGUP_TRACE.toggle(forceVisible)
    if type(forceVisible) == "boolean" then
        state.visible = forceVisible
    else
        state.visible = not state.visible
    end
    return state.visible
end

function TAGUP_TRACE.isVisible()
    return state.visible
end

-- A local preview keeps visual QA independent from the mission state machine.
function TAGUP_TRACE.preview()
    if state.liveSequence then
        return false
    end
    TAGUP_TRACE.setSequence({
        {id = "intro", title = "Meet Sweet", detail = "Grove Street", status = "done"},
        {id = "drive", title = "Drive to Idlewood", detail = "Greenwood route", status = "done"},
        {id = "demo", title = "Watch the demonstration", detail = "Sweet is spraying", status = "active"},
        {id = "idlewood", title = "Cover two Ballas tags", detail = "Queued"},
        {id = "ballas", title = "Move into Ballas territory", detail = "Queued"},
        {id = "rooftop", title = "Reach the rooftop tag", detail = "Queued"},
        {id = "return", title = "Bring Sweet home", detail = "Queued"},
    }, {title = "TAGGING UP TURF", subtitle = "CO-OP MISSION TRACE"})
    TAGUP_TRACE.setCurrent("demo")
    TAGUP_TRACE.setProgress("demo", 0.62, "Spray demonstration 62%")
    TAGUP_TRACE.toggle(true)
    return true
end

local function getVisibleRange()
    local count = #state.steps
    if count <= MAX_VISIBLE_STEPS then
        return 1, count
    end

    local focus = state.currentIndex or 1
    local first = clamp(focus - 2, 1, count - MAX_VISIBLE_STEPS + 1)
    return first, first + MAX_VISIBLE_STEPS - 1
end

local function drawText(text, left, top, right, bottom, textColor, scale, font, alignX, alignY, opacity)
    local shadow = color({0, 0, 0, 180}, opacity)
    dxDrawText(text, left + scale, top + scale, right + scale, bottom + scale, shadow, scale, font, alignX, alignY, true, false, false, false)
    dxDrawText(text, left, top, right, bottom, textColor, scale, font, alignX, alignY, true, false, false, false)
end

local function getStatusVisual(step)
    if step.status == "active" then
        return palette.accent, "ACTIVE", 1
    elseif step.status == "done" then
        return palette.textMuted, "DONE", 0.52
    elseif step.status == "failed" then
        return palette.failed, "FAILED", 0.95
    elseif step.status == "skipped" then
        return palette.skipped, "SKIPPED", 0.46
    end
    return palette.queued, "NEXT", 0.40
end

local function drawEmptyState(x, y, width, scale, opacity)
    local height = 180 * scale
    dxDrawRectangle(x, y, width, height, color(palette.panel, opacity), false)
    dxDrawRectangle(x, y, width, 3 * scale, color(palette.accent, opacity), false)
    dxDrawRectangle(x, y, 3 * scale, height, color(palette.accent, opacity), false)
    dxDrawRectangle(x + width - 2 * scale, y, 2 * scale, height, color(palette.panelEdge, opacity), false)
    dxDrawRectangle(x, y + height - 2 * scale, width, 2 * scale, color(palette.panelEdge, opacity), false)
    drawText("MISSION TRACE", x + 26 * scale, y + 22 * scale, x + width - 22 * scale, y + 58 * scale, color(palette.accent, opacity), fonts.header.scale,
             fonts.header.value, "left", "center", opacity)
    drawText("No instruction sequence has been supplied.", x + 26 * scale, y + 72 * scale, x + width - 26 * scale, y + 106 * scale,
             color(palette.textMuted, opacity), fonts.body.scale, fonts.body.value, "left", "center", opacity)
    drawText("/taguptracepreview  -  local visual preview", x + 26 * scale, y + 124 * scale, x + width - 26 * scale, y + 158 * scale,
             color(palette.queued, opacity), fonts.footer.scale, fonts.footer.value, "left", "center", opacity)
end

local function renderTrace()
    local now = getTickCount()
    local delta = clamp(now - state.lastFrameTick, 0, 100)
    state.lastFrameTick = now

    local targetVisibility = state.visible and 1 or 0
    local visibilityStep = delta / 180
    if state.visibility < targetVisibility then
        state.visibility = math.min(targetVisibility, state.visibility + visibilityStep)
    elseif state.visibility > targetVisibility then
        state.visibility = math.max(targetVisibility, state.visibility - visibilityStep)
    end
    if state.visibility <= 0 then
        return
    end
    if isMTAWindowActive() or isTransferBoxActive() or isPlayerMapVisible() then
        return
    end

    local screenWidth, screenHeight = guiGetScreenSize()
    local scale = clamp(math.min(screenWidth / DESIGN_WIDTH, screenHeight / DESIGN_HEIGHT), 0.65, 1.4)
    local opacity = easeOutCubic(state.visibility)
    local width = 590 * scale
    local x = screenWidth - width - 52 * scale
    local y = 145 * scale

    if #state.steps == 0 then
        drawEmptyState(x, y, width, scale, opacity)
        return
    end

    local first, last = getVisibleRange()
    local rowCount = last - first + 1
    local headerHeight = 108 * scale
    local rowHeight = 90 * scale
    local footerHeight = 44 * scale
    local panelHeight = headerHeight + rowCount * rowHeight + footerHeight
    local transition = easeOutCubic(clamp((now - state.transitionTick) / 320, 0, 1))

    dxDrawRectangle(x, y, width, panelHeight, color(palette.panel, opacity), false)
    dxDrawRectangle(x, y, width, headerHeight, color(palette.header, opacity), false)
    dxDrawRectangle(x, y, width, 3 * scale, color(palette.accent, opacity), false)
    dxDrawRectangle(x, y, 3 * scale, panelHeight, color(palette.accent, opacity), false)
    dxDrawRectangle(x + width - 2 * scale, y, 2 * scale, panelHeight, color(palette.panelEdge, opacity), false)
    dxDrawRectangle(x, y + panelHeight - 2 * scale, width, 2 * scale, color(palette.panelEdge, opacity), false)
    dxDrawRectangle(x, y + headerHeight - 2 * scale, width, 2 * scale, color(palette.panelEdge, opacity), false)

    local currentNumber = state.currentIndex or 0
    drawText(state.title, x + 26 * scale, y + 17 * scale, x + width - 120 * scale, y + 54 * scale, color(palette.accent, opacity), fonts.header.scale,
             fonts.header.value, "left", "center", opacity)
    drawText(("%02d / %02d"):format(currentNumber, #state.steps), x + width - 114 * scale, y + 17 * scale, x + width - 24 * scale, y + 54 * scale,
             color(palette.accent, opacity), fonts.title.scale, fonts.title.value, "right", "center", opacity)
    drawText(state.subtitle, x + 26 * scale, y + 62 * scale, x + width - 24 * scale, y + 91 * scale, color(palette.textMuted, opacity), fonts.body.scale,
             fonts.body.value, "left", "center", opacity)

    local rowsTop = y + headerHeight

    for visibleIndex = 0, rowCount - 1 do
        local index = first + visibleIndex
        local step = state.steps[index]
        local rowY = rowsTop + visibleIndex * rowHeight
        local visualColor, statusLabel, statusOpacity = getStatusVisual(step)
        local rowOpacity = opacity * statusOpacity
        local isActive = step.status == "active"

        step.displayProgress = step.displayProgress + (step.progress - step.displayProgress) * math.min(1, delta / 140)

        if isActive then
            dxDrawRectangle(x + 3 * scale, rowY, width - 5 * scale, rowHeight, color(palette.accentSoft, opacity * (0.82 + 0.18 * transition)), false)
            dxDrawRectangle(x + 3 * scale, rowY, 7 * scale, rowHeight, color(palette.accent, opacity), false)
        end

        drawText(("%02d"):format(index), x + 19 * scale, rowY + 12 * scale, x + 55 * scale, rowY + 43 * scale, color(visualColor, rowOpacity),
                 fonts.status.scale, fonts.status.value, "center", "center", rowOpacity)
        local contentX = x + 64 * scale
        drawText(step.title, contentX, rowY + 11 * scale, x + width - 112 * scale, rowY + 44 * scale,
                 color(isActive and palette.accent or palette.text, rowOpacity), fonts.title.scale,
                 fonts.title.value, "left", "center", rowOpacity)
        drawText(step.detail or "", contentX, rowY + 47 * scale, x + width - 112 * scale, rowY + 73 * scale, color(palette.textMuted, rowOpacity),
                 fonts.body.scale, fonts.body.value, "left", "center", rowOpacity)
        drawText(statusLabel, x + width - 106 * scale, rowY + 13 * scale, x + width - 22 * scale, rowY + 42 * scale, color(visualColor, rowOpacity),
                 fonts.status.scale, fonts.status.value, "right", "center", rowOpacity)

        if isActive or step.displayProgress > 0 then
            local progressX = contentX
            local progressY = rowY + rowHeight - 10 * scale
            local progressWidth = width - (contentX - x) - 22 * scale
            dxDrawRectangle(progressX, progressY, progressWidth, 3 * scale, color(palette.track, rowOpacity), false)
            dxDrawRectangle(progressX, progressY, progressWidth * step.displayProgress, 3 * scale, color(visualColor, rowOpacity), false)
        end
    end

    local hiddenBefore = first - 1
    local hiddenAfter = #state.steps - last
    local rangeLabel
    if hiddenBefore > 0 or hiddenAfter > 0 then
        rangeLabel = ("%d earlier  /  %d queued"):format(hiddenBefore, hiddenAfter)
    else
        rangeLabel = "FULL SEQUENCE"
    end
    local footerY = y + panelHeight - footerHeight
    drawText(rangeLabel, x + 26 * scale, footerY, x + width - 175 * scale, y + panelHeight, color(palette.queued, opacity), fonts.footer.scale,
             fonts.footer.value, "left", "center", opacity)
    drawText(TOGGLE_KEY .. " // HIDE", x + width - 165 * scale, footerY, x + width - 22 * scale, y + panelHeight, color(palette.accent, opacity),
             fonts.status.scale, fonts.status.value, "right", "center", opacity)
end

local function toggleFromInput(sourceName, argument)
    if sourceName ~= "taguptrace" and
        (isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isTransferBoxActive() or isCursorShowing() or guiGetInputEnabled() or
            isPlayerMapVisible()) then
        return
    end

    local forced
    if sourceName == "taguptrace" and type(argument) == "string" and argument ~= "" then
        argument = string.lower(argument)
        if argument == "on" or argument == "1" or argument == "true" then
            forced = true
        elseif argument == "off" or argument == "0" or argument == "false" then
            forced = false
        else
            outputChatBox("[Tag trace] Usage: /taguptrace [on|off].", 244, 180, 100)
            return
        end
    end

    local visible = TAGUP_TRACE.toggle(forced)
    outputChatBox(("[Tag trace] %s. Toggle: /taguptrace or %s."):format(visible and "visible" or "hidden", TOGGLE_KEY), 145, 220, 175)
end

addCommandHandler("taguptrace", toggleFromInput)
addCommandHandler("taguptracepreview", function()
    if TAGUP_TRACE.preview() then
        outputChatBox("[Tag trace] Local preview loaded. It is not connected to mission state.", 145, 220, 175)
    else
        outputChatBox("[Tag trace] Preview unavailable while a live mission trace is active.", 244, 180, 100)
    end
end)
bindKey(TOGGLE_KEY, "down", toggleFromInput)
addEventHandler("onClientRender", root, renderTrace, true, "high+10")
