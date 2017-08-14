WebClient = {};

local types = {};
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.Xml.XmlTextReader"] = luanet.import_type("System.Xml.XmlTextReader");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");

-- Create a logger
local log = types["log4net.LogManager"].GetLogger(rootLogger .. ".AlmaApi");

local function GetRequest(requestUrl, headers)
    local webClient = types["System.Net.WebClient"]();
    local response = nil;
    log:Debug("Created Web Client");
    webClient.Encoding = types["System.Text.Encoding"].UTF8;

    for _, header in ipairs(headers) do
        webClient.Headers:Add(header);
    end

    local success, error = pcall(function ()
        response = webClient:DownloadString(requestUrl);
    end);

    webClient:Dispose();
    log:Debug("Disposed Web Client");

    if(success) then
        return response;
    else
        log:InfoFormat("Unable to get response from the request url: {0}", error);
    end
end

--Exports
WebClient.GetRequest = GetRequest;