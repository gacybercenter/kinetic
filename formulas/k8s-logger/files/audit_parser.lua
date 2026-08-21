-- Function to decode hex-encoded proctitle to a human-readable string
local function decode_proctitle(hex)
    -- Convert hex string to ASCII, replacing null bytes with spaces
    local decoded = hex:gsub("%x%x", function(h)
        local byte = tonumber(h, 16)
        if byte == 0 then
            return " " -- Replace null byte with space
        else
            return string.char(byte)
        end
    end)
    return decoded
end

-- Function to split a string by spaces, handling quoted strings
local function split_fields(str)
    local fields = {}
    local current = ""
    local in_quotes = false
    local i = 1

    while i <= #str do
        local char = str:sub(i, i)
        if char == '"' and str:sub(i-1, i-1) ~= "\\" then
            in_quotes = not in_quotes
            current = current .. char
        elseif char == " " and not in_quotes then
            if current ~= "" then
                table.insert(fields, current)
                current = ""
            end
        else
            current = current .. char
        end
        i = i + 1
    end
    if current ~= "" then
        table.insert(fields, current)
    end
    return fields
end

-- Function to parse a single audit log line into key-value pairs
local function parse_audit_log_line(log)
    local result = {}
    -- Preprocess to replace \x1D (group separator, ASCII 29) with a space
    log = log:gsub("\29", " ")

    -- Log the preprocessed line for debugging
    local f = io.open("/tmp/fluentbit_preprocessed_log.log", "a")
    f:write("Preprocessed log line: " .. log .. "\n")
    f:close()

    -- Handle msg=audit(...) separately to avoid splitting inside parentheses
    local msg_match = log:match("msg=audit%([^%)]+%):")
    if msg_match then
        result["msg"] = msg_match
        log = log:gsub(msg_match, "", 1) -- Remove msg field
    end

    -- Split the remaining log into fields
    local fields = split_fields(log)

    -- Log raw fields for debugging
    local f = io.open("/tmp/fluentbit_raw_fields.log", "a")
    f:write("Raw fields:\n")
    for _, field in ipairs(fields) do
        f:write("  " .. field .. "\n")
    end
    f:close()

    -- Process each field
    for _, field in ipairs(fields) do
        -- Match key=value pairs (handles quoted and unquoted values)
        local key, value = field:match("^(%w+)=(.-)$")
        if key and value then
            -- Remove surrounding quotes if present
            if value:match('^".*"$') then
                value = value:sub(2, -2)
            end
            result[key] = value
            -- Decode proctitle if present
            if key == "proctitle" then
                result["proctitle_decoded"] = decode_proctitle(value)
            end
        else
            -- Log parsing errors for debugging
            local f = io.open("/tmp/fluentbit_parse_errors.log", "a")
            f:write("Failed to parse field: " .. field .. "\n")
            f:close()
        end
    end

    return result
end

-- Fluent Bit filter callback function
function cb_filter(tag, timestamp, record)
    -- Assume the audit log line is in the 'log' field of the record
    local log_line = record.log
    if not log_line then
        -- Log error if no 'log' field
        local f = io.open("/tmp/fluentbit_parse_errors.log", "a")
        f:write("No 'log' field in record for tag: " .. tag .. "\n")
        f:close()
        return 0, timestamp, record
    end

    -- Log the raw log line for debugging
    local f = io.open("/tmp/fluentbit_raw_log.log", "a")
    f:write("Raw log line: " .. log_line .. "\n")
    f:close()

    -- Parse the audit log line into key-value pairs
    local parsed = parse_audit_log_line(log_line)

    -- Create a new record by merging the original record with parsed fields
    local new_record = {}
    for k, v in pairs(record) do
        new_record[k] = v
    end
    for k, v in pairs(parsed) do
        new_record[k] = v
    end

    -- Log the parsed record for debugging
    local f = io.open("/tmp/fluentbit_parse_debug.log", "a")
    f:write("Parsed record for tag " .. tag .. ":\n")
    for k, v in pairs(new_record) do
        f:write("  " .. k .. ": " .. tostring(v) .. "\n")
    end
    f:close()

    -- Return modified record
    return 1, timestamp, new_record
end