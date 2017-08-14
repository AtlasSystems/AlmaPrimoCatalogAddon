local settings = {};
settings.AutoSearch = GetSetting("AutoSearch");
settings.AvailableSearchTypes = Utility.StringSplit(",", GetSetting("AvailableSearchTypes"));
settings.SearchPriorityList = Utility.StringSplit(",", GetSetting("SearchPriorityList"));
settings.HomeUrl = GetSetting("HomeURL");
settings.CatalogUrl = GetSetting("CatalogURL");
settings.AutoRetrieveItems = GetSetting("AutoRetrieveItems");
settings.RemoveTrailingSpecialCharacters = GetSetting("RemoveTrailingSpecialCharacters");
settings.AlmaApiUrl = GetSetting("AlmaAPIURL");
settings.AlmaApiKey = GetSetting("AlmaAPIKey");
settings.PrimoSiteCode = GetSetting("PrimoSiteCode");
settings.MmsIdRegex = GetSetting("MmsIdRegex");

local interfaceMngr = nil;

-- The catalogSearchForm table allows us to store all objects related to the specific form inside the table so that we can easily
-- prevent naming conflicts if we need to add more than one form and track elements from both.
local catalogSearchForm = {};
catalogSearchForm.Form = nil;
catalogSearchForm.Browser = nil;
catalogSearchForm.RibbonPage = nil;
catalogSearchForm.ItemsButton = nil;
catalogSearchForm.ImportButton = nil;
catalogSearchForm.SearchButtons = {};
catalogSearchForm.SearchButtons["Home"] = nil;
catalogSearchForm.SearchButtons["Title"] = nil;
catalogSearchForm.SearchButtons["Author"] = nil;
catalogSearchForm.SearchButtons["CallNumber"] = nil;
catalogSearchForm.SearchButtons["CatalogNumber"] = nil;
catalogSearchForm.SearchButtons["Subject"] = nil;
catalogSearchForm.SearchButtons["ISBN"] = nil;
catalogSearchForm.SearchButtons["ISSN"] = nil;

local itemsXmlDocCache = {};

luanet.load_assembly("System.Data");
luanet.load_assembly("System.Drawing");
luanet.load_assembly("System.Xml");
luanet.load_assembly("System.Windows.Forms");
luanet.load_assembly("DevExpress.XtraBars");
luanet.load_assembly("log4net");

local types = {};
types["System.Data.DataTable"] = luanet.import_type("System.Data.DataTable");
types["System.Drawing.Size"] = luanet.import_type("System.Drawing.Size");
types["DevExpress.XtraBars.BarShortcut"] = luanet.import_type("DevExpress.XtraBars.BarShortcut");
types["System.Windows.Forms.Shortcut"] = luanet.import_type("System.Windows.Forms.Shortcut");
types["System.Windows.Forms.Keys"] = luanet.import_type("System.Windows.Forms.Keys");
types["System.DBNull"] = luanet.import_type("System.DBNull");
types["System.Windows.Forms.Application"] = luanet.import_type("System.Windows.Forms.Application");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");

local rootLogger = "AtlasSystems.Addons.AlmaPrimoCatalogSearch";
local log = types["log4net.LogManager"].GetLogger(rootLogger);
local product = types["System.Windows.Forms.Application"].ProductName;
log:Debug("Finished creating types");

function Init()
    interfaceMngr = GetInterfaceManager();

    -- Create a form
    catalogSearchForm.Form = interfaceMngr:CreateForm(DataMapping.LabelName, DataMapping.LabelName);

    -- Add a browser
    catalogSearchForm.Browser = catalogSearchForm.Form:CreateBrowser(DataMapping.LabelName, "Catalog Search Browser", DataMapping.LabelName);
    -- Hide the text label
    catalogSearchForm.Browser.TextVisible = false;
    catalogSearchForm.Browser.WebBrowser.ScriptErrorsSuppressed = true;

    -- Since we didn't create a ribbon explicitly before creating our browser, it will have created one using the name we passed the CreateBrowser method.  We can retrieve that one and add our buttons to it.
    catalogSearchForm.RibbonPage = catalogSearchForm.Form:GetRibbonPage(DataMapping.LabelName);

    -- Create the search button(s)
    catalogSearchForm.SearchButtons["Home"] = catalogSearchForm.RibbonPage:CreateButton("New Search", GetClientImage(DataMapping.Icons[product]["Web"]), "ShowCatalogHome", "Search Options");

    for _, searchType in ipairs(settings.AvailableSearchTypes) do
        local variableName = Utility.RemoveWhiteSpaceFromString(searchType);
        log:DebugFormat("Variable Name = {0}", variableName);
        catalogSearchForm.SearchButtons[variableName] = catalogSearchForm.RibbonPage:CreateButton(searchType, GetClientImage(DataMapping.Icons[product]["Search"]), "Search" .. variableName, "Search Options");
    end

    if (not settings.AutoRetrieveItems) then
        catalogSearchForm.ItemsButton = catalogSearchForm.RibbonPage:CreateButton("Retrieve Items", GetClientImage(DataMapping.Icons[product]["Record"]), "RetrieveItems", "Process");
        catalogSearchForm.ItemsButton.BarButton.ItemShortcut = types["DevExpress.XtraBars.BarShortcut"](types["System.Windows.Forms.Shortcut"].CtrlR);
    end;

    catalogSearchForm.ImportButton = catalogSearchForm.RibbonPage:CreateButton("Import", GetClientImage(DataMapping.Icons[product]["Import"]), "DoItemImport", "Process");
    catalogSearchForm.ImportButton.BarButton.ItemShortcut = types["DevExpress.XtraBars.BarShortcut"](types["System.Windows.Forms.Shortcut"].CtrlI);
    catalogSearchForm.ImportButton.BarButton.Enabled = false;

    BuildItemsGrid();

    catalogSearchForm.Form:LoadLayout("CatalogLayout.xml");

    -- After we add all of our buttons and form elements, we can show the form.
    catalogSearchForm.Form:Show();

    -- Initializing the AlmaApi
    AlmaApi.ApiUrl = settings.AlmaApiUrl;
    AlmaApi.ApiKey = settings.AlmaApiKey;

    -- Search when opened if autoSearch is true
    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");
    if ((settings.AutoSearch) and (transactionNumber) and (transactionNumber > 0)) then
        log:Debug("Performing AutoSearch");
        PerformSearch(true, nil);
    else
        log:Debug("Navigating to Catalog URL because AutoSearch is disabled");
        ShowCatalogHome();
    end

end

function InitializeRecordPageHandler()
    catalogSearchForm.Browser:RegisterPageHandler("custom", "IsRecordPageLoaded", "RecordPageHandler", false);
end

function ShowCatalogHome()
    InitializeRecordPageHandler();
    catalogSearchForm.Browser:Navigate(settings.HomeUrl);
end

-- Search Functions
function SearchTitle()
    PerformSearch(false, "Title");
end

function SearchAuthor()
    PerformSearch(false, "Author");
end

function SearchCallNumber()
    PerformSearch(false, "Call Number");
end

function SearchSubject()
    PerformSearch(false, "Subject");
end

function SearchISBN()
    PerformSearch(false, "ISBN");
end

function SearchISSN()
    PerformSearch(false, "ISSN");
end

function SearchCatalogNumber()
    PerformSearch(false, "Catalog Number");
end

function GetAutoSearchType()
    local priorityList = settings.SearchPriorityList;
    local fieldValue = nil;

    for index = 1, #priorityList do
        if DataMapping.SearchTypes[priorityList[index]] ~= nil and DataMapping.SourceFields[product][priorityList[index]] ~= nil then
            fieldValue = GetFieldValue("Transaction", DataMapping.SourceFields[product][priorityList[index]]);
            log:DebugFormat("fieldValue = {0}", fieldValue);
            if fieldValue and fieldValue ~= "" then
                return priorityList[index];
            end
        end
    end

    return nil;
end

function PerformSearch(autoSearch, searchType)
    InitializeRecordPageHandler();
    if (searchType == nil) then
        searchType = GetAutoSearchType();
        log:DebugFormat("Auto-Search Type = {0}", searchType);
        if searchType == nil then
            local searchTypeError = "The search type could not be determined using the current request information.";

            if (autoSearch) then
                catalogSearchForm.Browser.WebBrowser.DocumentText = searchTypeError;
                log:Error(searchTypeError);
            else
                -- Should only be reachable if a search button didn't include a search type
                interfaceMngr:ShowMessage(searchTypeError, "No Search Type Specified");
            end

            return;
        end
    end

    local searchTerm = GetFieldValue("Transaction", DataMapping.SourceFields[product][searchType]);

    if (searchTerm == nil) then
        searchTerm = "";
    end

    local searchUrl = "";

    --Construct the search url based on the base catalog url, the search prefix that is defined in DataMapping for each MapType, followed by the search term
    searchUrl = settings.CatalogUrl .. "search?vid=" .. settings.PrimoSiteCode .. "&query=" .. DataMapping.SearchTypes[searchType] .. ",contains," .. Utility.URLEncode(searchTerm) .. ",AND&search_scope=default_scope&mode=advanced";

    log:DebugFormat("Navigating to {0}", searchUrl);
    catalogSearchForm.Browser:Navigate(searchUrl);
end

function GetMmsId(webPage)
    log:Debug("Getting MMS ID...");

    if (webPage == nil) then
        log:Warn("webPage was nil");
        return nil;
    end

    local iframes = webPage:GetElementsByTagName("iframe");
    log:DebugFormat("Number of iFrames = {0}", iframes.Count);

    if(iframes.Count > 0) then
        -- Loop through the list of iframes until we get an mms id
        for i = 0, iframes.Count - 1 do
            local iframe = iframes:get_Item(i);
            local src = ExtractIFrameSrc(iframe);

            if(src ~= nil and src ~= "") then
                log:DebugFormat("src = {0}", src);
                local iframeContents = WebClient.GetRequest(src, {});
                local mmsId = ExtractMmsIdFromIFrame(iframeContents);
                if(mmsId ~= nil and mmsId ~= "") then
                    return mmsId;
                end
            end
        end
    end

    return nil;
end

function ExtractIFrameSrc(iframe)
    local src = iframe:GetAttribute("src");
    if(src ~= nil and src ~= "") then
        return src;
    end
    return nil;
end

function ExtractMmsIdFromIFrame(iframeContents)
    local mmsId = RegEx.Match(DataMapping.MmsIdRegex, iframeContents);
    log:DebugFormat("mmsId = {0}", mmsId.Groups["mmsId"].Value);
    if(mmsId ~= nil and mmsId ~= "" ) then
        return mmsId.Groups["mmsId"].Value;
    else
        return nil;
    end
end

function IsRecordPageLoaded()
    log:Debug("Checking if Record Page is loaded");

    -- Toggling off UI Elements before another record page can load
    ToggleItemsUIElements(false);

    local webPage = catalogSearchForm.Browser.WebBrowser.Document;
    local pageUrl = catalogSearchForm.Browser.WebBrowser.Url:ToString();
    local mmsId = GetMmsId(catalogSearchForm.Browser.WebBrowser.Document);
    local isRecordPage = mmsId ~= nil and mmsId ~= "";

    if isRecordPage then
        log:DebugFormat("Is a record page. {0}", pageUrl);
    else
        log:DebugFormat("Is not a record page. {0}", pageUrl);
        ToggleItemsUIElements(false);
    end

    return isRecordPage;
end

function RecordPageHandler()
    --The record page has been loaded. We now need to wait to see when the holdings information comes in.
    ToggleItemsUIElements(true);

    --Re-initialize the record page handler in case the user navigates away from a record page to search again
    InitializeRecordPageHandler();

    return itemPageChanged;
end

function Truncate(value, size)
    if size == nil then
        log:Debug("Size was nil. Truncating to 50 characters");
        size = 50;
    end
    if ((value == nil) or (value == "")) then
        log:Debug("Value was nil or empty. Skipping truncation.");
        return value;
    else
        log:DebugFormat("Truncating to {0} characters: {1}", size, value);
        return string.sub(value, 0, size);
    end
end

function ImportField(target, newFieldValue, targetSize)
    if ((newFieldValue ~= nil) and (newFieldValue ~= "") and (newFieldValue ~= types["System.DBNull"].Value)) then
        SetFieldValue("Transaction", target, Truncate(newFieldValue, targetSize));
    end
end

function ToggleItemsUIElements(enabled)
    if (enabled) then
        log:Debug("Enabling UI.");
        if (settings.AutoRetrieveItems) then
            local hasRecords = RetrieveItems();
            catalogSearchForm.Grid.GridControl.Enabled = hasRecords;
        else
            catalogSearchForm.ItemsButton.BarButton.Enabled = true;
            -- If there's an item in the Item Grid
            if(catalogSearchForm.Grid.GridControl.MainView.FocusedRowHandle > -1) then
                catalogSearchForm.Grid.GridControl.Enabled = true;
                catalogSearchForm.ImportButton.BarButton.Enabled = true;
            end
        end
    else
        log:Debug("Disabling UI.");
        ClearItems();
        catalogSearchForm.Grid.GridControl.Enabled = false;
        catalogSearchForm.ImportButton.BarButton.Enabled = false;

        if (not settings.AutoRetrieveItems) then
            catalogSearchForm.ItemsButton.BarButton.Enabled = false;
        end
    end
    log:Debug("Finished Toggling UI Elements");
end

function BuildItemsGrid()
    log:Debug("BuildItemsGrid");

    catalogSearchForm.Grid = catalogSearchForm.Form:CreateGrid("CatalogItemsGrid", "Items");
    catalogSearchForm.Grid.GridControl.Enabled = false;

    catalogSearchForm.Grid.TextSize = types["System.Drawing.Size"].Empty;
    catalogSearchForm.Grid.TextVisible = false;

    local gridControl = catalogSearchForm.Grid.GridControl;

    gridControl:BeginUpdate();

    -- Set the grid view options
    local gridView = gridControl.MainView;
    gridView.OptionsView.ShowIndicator = false;
    gridView.OptionsView.ShowGroupPanel = false;
    gridView.OptionsView.RowAutoHeight = true;
    gridView.OptionsView.ColumnAutoWidth = true;
    gridView.OptionsBehavior.AutoExpandAllGroups = true;
    gridView.OptionsBehavior.Editable = false;

    -- Item Grid Column Settings
    local gridColumn;
    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "MMS ID";
    gridColumn.FieldName = "ReferenceNumber";
    gridColumn.Name = "gridColumnReferenceNumber";
    gridColumn.Visible = false;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Holding ID";
    gridColumn.FieldName = "HoldingId";
    gridColumn.Name = "gridColumnHoldingId";
    gridColumn.Visible = false;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Location";
    gridColumn.FieldName = "Location";
    gridColumn.Name = "gridColumnLocation";
    gridColumn.Visible = true;
    gridColumn.VisibleIndex = 0;
    gridColumn.OptionsColumn.ReadOnly = true;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Location Code";
    gridColumn.FieldName = "Library";
    gridColumn.Name = "gridColumnLibrary";
    gridColumn.Visible = false;
    gridColumn.OptionsColumn.ReadOnly = true;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Call Number";
    gridColumn.FieldName = "CallNumber";
    gridColumn.Name = "gridColumnCallNumber";
    gridColumn.Visible = true;
    gridColumn.VisibleIndex = 1;
    gridColumn.OptionsColumn.ReadOnly = true;

    gridControl:EndUpdate();

    gridView:add_FocusedRowChanged(ItemsGridFocusedRowChanged);
end

function ItemsGridFocusedRowChanged(sender, args)
    if (args.FocusedRowHandle > -1) then
        catalogSearchForm.ImportButton.BarButton.Enabled = true;
        catalogSearchForm.Grid.GridControl.Enabled = true;
    else
        catalogSearchForm.ImportButton.BarButton.Enabled = false;
    end;
end

function RetrieveItems()
    local mmsId = GetMmsId(catalogSearchForm.Browser.WebBrowser.Document);
    local apiKey = settings.AlmaApiKey;
    local apiUrl = settings.AlmaApiUrl;

-- Cache the response if it hasn't been cached
    if (itemsXmlDocCache[mmsId] == nil) then
        log:DebugFormat("Caching {0}", mmsId);
        itemsXmlDocCache[mmsId] = AlmaApi.RetrieveHoldingsList(mmsId);
    end

    local response = itemsXmlDocCache[mmsId];

    -- Check if it has any items available
    local totalRecordCount = tonumber(response:SelectSingleNode("holdings/@total_record_count").Value);
    log:DebugFormat("Records Available: {0}", totalRecordCount);

    local hasRecords = totalRecordCount > 0;
    if (hasRecords) then
        -- Fill out Holdings Grid if there are items available
        PopulateItemsDataSources( response, mmsId )
    else
        ClearItems();
    end;

    return hasRecords;
end

function CreateItemsTable()
    local itemsTable = types["System.Data.DataTable"]();

    itemsTable.Columns:Add("ReferenceNumber");
    itemsTable.Columns:Add("HoldingId");
    itemsTable.Columns:Add("Library");
    itemsTable.Columns:Add("Location");
    itemsTable.Columns:Add("CallNumber");

    return itemsTable;
end

function ClearItems()
    catalogSearchForm.Grid.GridControl:BeginUpdate();
    catalogSearchForm.Grid.GridControl.DataSource = CreateItemsTable();
    catalogSearchForm.Grid.GridControl:EndUpdate();
end

function BuildItemsDataSource(holdingsXmlDoc, mmsId)
    local itemsDataTable = CreateItemsTable();

    local itemNodes = holdingsXmlDoc:GetElementsByTagName("holding");
    log:DebugFormat("Holding nodes found: {0}", itemNodes.Count);

    for i = 0, itemNodes.Count - 1 do
        local itemRow = itemsDataTable:NewRow();
        local itemNode = itemNodes:Item(i);
        log:DebugFormat("itemNode = {0}", itemNode.OuterXml);

        itemRow:set_Item("ReferenceNumber", mmsId);
        log:DebugFormat("Reference Number = {0}", mmsId);

        itemRow:set_Item("HoldingId", itemNode["holding_id"].InnerXml);
        log:DebugFormat("HoldingId = {0}", itemNode["holding_id"].InnerXml);

        -- If the location isn't specified in the Customized Mapping, use the location code
        if(CustomizedMapping.Locations[itemNode["location"].InnerXml] ~= nil and CustomizedMapping.Locations[itemNode["location"].InnerXml] ~= "") then
            itemRow:set_Item("Location", CustomizedMapping.Locations[itemNode["location"].InnerXml]);
            log:DebugFormat("Location = {0}", CustomizedMapping.Locations[itemNode["location"].InnerXml]);
        else
            itemRow:set_Item("Location", itemNode["location"].InnerXml);
            log:DebugFormat("Location = {0}", itemNode["location"].InnerXml);
        end

        itemRow:set_Item("Library", itemNode["library"].InnerXml);
        log:DebugFormat("Library = {0}", itemNode["library"].InnerXml);

        itemRow:set_Item("CallNumber", itemNode["call_number"].InnerXml);
        log:DebugFormat("CallNumber = {0}", itemNode["call_number"].InnerXml);

        itemsDataTable.Rows:Add(itemRow);
    end

    return itemsDataTable;
end

function PopulateItemsDataSources( response, mmsId )
    log:DebugFormat("response type = {0}", response);
    catalogSearchForm.Grid.GridControl:BeginUpdate();
    catalogSearchForm.Grid.GridControl.DataSource = BuildItemsDataSource(response, mmsId);
    catalogSearchForm.Grid.GridControl:EndUpdate();
    catalogSearchForm.Grid.GridControl:Focus();
end

function DoItemImport()
    log:Debug("Performing Import");

    log:Debug("Retrieving import row.");
    local importRow = catalogSearchForm.Grid.GridControl.MainView:GetFocusedRow();

    if (importRow == nil) then
        log:Debug("Import row was nil.  Cancelling the import.");
        return;
    end;

    -- Update the transaction object with values.
    log:Debug("Updating the transaction object.");

    -- Import the Holdings Information
    for _, target in ipairs(DataMapping.ImportFields.Holding[product]) do
        ImportField(target.Field, importRow:get_Item(target.Value), target.MaxSize);
    end

    local bibliographicInformation = GetBibliographicInformation();

    for _, target in ipairs(bibliographicInformation) do
        log:DebugFormat("Importing {0}, {1}, {2}", target.Field, target.Value, target.MaxSize);
        ImportField(target.Field, target.Value, target.MaxSize);
    end

    log:Debug("Switching to the detail tab.");
    ExecuteCommand("SwitchTab", "Detail");
end

function GetBibliographicInformation()
    local bibliographicInformation = {};

    local mmsId = GetMmsId(catalogSearchForm.Browser.WebBrowser.Document);
    local apiUrl = settings.AlmaApiUrl;
    local apiKey = settings.AlmaApiKey;
    local bibXmlDoc = AlmaApi.RetrieveBibs(mmsId);

    local recordNodes = bibXmlDoc:SelectNodes("//record");

    if (recordNodes) then
        log:DebugFormat("Found {0} MARC records", recordNodes.Count);

        -- Loops through each record
        for recordNodeIndex = 0, (recordNodes.Count - 1) do
            log:DebugFormat("Processing record {0}", recordNodeIndex);
            local recordNode = recordNodes:Item(recordNodeIndex);

            -- Loops through each Bibliographic mapping
            for _, target in ipairs(DataMapping.ImportFields.Bibliographic[product]) do
                if (target and target.Field and target.Field ~= "") then
                    log:DebugFormat("Value: {0}", target.Value);
                    log:DebugFormat("Target: {0}", target.Field);
                    local marcSets = Utility.StringSplit(',', target.Value );
                    log:DebugFormat("marcSets.Count = {0}", #marcSets);

                    -- Loops through the MARC sets array
                    for _, xPath in ipairs(marcSets) do
                        log:DebugFormat("xPath = {0}", xPath);
                        local datafieldNode = recordNode:SelectNodes(xPath);
                        log:DebugFormat("DataField Node Match Count: {0}", datafieldNode.Count);

                        if (datafieldNode.Count > 0) then
                            local fieldValue = "";

                            -- Loops through each data field node retured from xPath and concatenates them (generally only 1)
                            for datafieldNodeIndex = 0, (datafieldNode.Count - 1) do
                                log:DebugFormat("datafieldnode value is: {0}", datafieldNode:Item(datafieldNodeIndex).InnerText);
                                fieldValue = fieldValue .. " " .. datafieldNode:Item(datafieldNodeIndex).InnerText;
                            end

                            log:DebugFormat("target.Field: {0}", target.Field);
                            log:DebugFormat("target.MaxSize: {0}", target.MaxSize);

                            if(settings.RemoveTrailingSpecialCharacters) then
                                fieldValue = Utility.RemoveTrailingSpecialCharacters(fieldValue);
                            else
                                fieldValue = Utility.Trim(fieldValue);
                            end

                            AddBibliographicInformation(bibliographicInformation, target.Field, fieldValue, target.MaxSize);

                            -- Need to break from MARC Set loop so the first record isn't overwritten
                            break;
                        end
                    end
                end
            end
        end
    end

    return bibliographicInformation;
end

function AddBibliographicInformation(bibliographicInformation, targetField, fieldValue, targetMaxSize)
    local bibInfoEntry = {Field = targetField, Value = fieldValue, MaxSize = targetMaxSize}
    table.insert( bibliographicInformation, bibInfoEntry );
end