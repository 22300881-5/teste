return function(webhookURL, message)
    local HttpService = game:GetService("HttpService")

    local data = { content = message }
    local jsonData = HttpService:JSONEncode(data)

    local headers = { ["Content-Type"] = "application/json" }

    local success, response = pcall(function()
        return HttpService:PostAsync(webhookURL, jsonData, Enum.HttpContentType.ApplicationJson, false, headers)
    end)

    if success then
        print("✅ Mensagem enviada com sucesso!")
    else
        warn("❌ Erro ao enviar mensagem: " .. tostring(response))
    end
end
