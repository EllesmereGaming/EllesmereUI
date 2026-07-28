-- C_QuestLog
if not C_QuestLog then
    C_QuestLog = {}

    C_QuestLog.GetNumQuestLogEntries = function()
        return GetNumQuestLogEntries()
    end

    C_QuestLog.GetLogIndexForQuestID = function(questID)
        local num = GetNumQuestLogEntries()
        for i = 1, num do
            local _, _, _, _, _, _, _, _, qID = GetQuestLogTitle(i)
            if qID == questID then
                return i
            end
        end
        return nil
    end

    C_QuestLog.IsOnQuest = function(questID)
        return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    end

    C_QuestLog.GetInfo = function(index)
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID, startEvent = GetQuestLogTitle(index)
        if title then
            local complete = (isComplete == 1 or isComplete == true)
            return {
                title = title,
                level = level,
                questClassification = questTag,
                frequency = isDaily and 1 or 0,
                isHeader = isHeader,
                isCollapsed = isCollapsed,
                isComplete = complete,
                questID = questID,
            }
        end
        return nil
    end

    C_QuestLog.IsComplete = function(questID)
        local idx = C_QuestLog.GetLogIndexForQuestID(questID)
        if idx then
            local info = C_QuestLog.GetInfo(idx)
            return info and info.isComplete or false
        end
        return false
    end

    C_QuestLog.GetQuestWatchType = function(questID)
        return 0
    end
end

-- C_PlayerInteractionManager
if not C_PlayerInteractionManager then
    C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function(type)
            return false
        end
    }
end

-- C_AddOnProfiler
if not C_AddOnProfiler then
    C_AddOnProfiler = {
        GetAddOnMetric = function() return 0 end,
    }
end
