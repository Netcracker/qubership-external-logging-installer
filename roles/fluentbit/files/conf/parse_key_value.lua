function cb_split(tag, timestamp, record)
    if record["log"] ~= nil and type(record["log"]) ~= "table" then
        pttrn = "%[([^=%[%]]+)=(%w+)%]"
        s = record["log"]
        for k, v in string.gmatch(s, pttrn) do
          record[k] = v
        end
        return 1, timestamp, record
    else
        return 1, timestamp, record
    end
end