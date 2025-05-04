local asset = require(136961041832048)
local assets = {asset("Iris"), asset("wav_player"), asset("fft_emitter")}

local NMS = require(106126121742989).NMS

local source = [==========[
local wav_player = require(script:WaitForChild("wav_player"))
local fft_emitter = require(script:WaitForChild("fft_emitter"))

local player = wav_player.new(1024)
local emitter = fft_emitter.new()

local global = false
local isloading = false
local lplr = game:GetService("Players").LocalPlayer
local owner = script:WaitForChild("owner").Value

task.spawn(function()
	while true do

		if owner then
			if owner == lplr or global then
				emitter.Parent = workspace.CurrentCamera
			else
				local char = owner.Character
				if char then
					emitter.Parent = char:FindFirstChild("HumanoidRootPart")
				end
			end
		end

		local listener = workspace.CurrentCamera:FindFirstChild("fft_listener")
		if not listener then
			listener = Instance.new("AudioListener")
			listener.Name = "fft_listener"
			listener.AudioInteractionGroup = "fft"
			listener.Parent = workspace.CurrentCamera

			local out = Instance.new("AudioDeviceOutput")
			out.Parent = listener

			local wire = Instance.new("Wire")
			wire.SourceInstance = listener
			wire.TargetInstance = out
			wire.Parent = listener
		end

		task.wait()
	end
end)

player:PipeEmitter(emitter)

local remote = script.RemoteEvent
local req_load = false
local loaded_chunks = {}

local function process_event(action, data, ...)
	local is_local = lplr == owner

	if action == "toggle" then
		if data and not player.IsPlaying then
			player:Play()
		elseif not data and player.IsPlaying then
			player:Pause()
		end
	elseif action == "stop" then
		player:Stop()
	elseif action == "global" then
		global = data
	elseif action == "load" then
		if typeof(data) == "string" and not select(1, ...) then
			warn("server failed to load wav")
			warn(data)
			isloading = false
			return
		end
		local chunk_id = data
		if chunk_id == 1 then
			loaded_chunks = {}
			print("start wav recieve")
		end

		print("recieved wav chunk " .. chunk_id)

		table.insert(loaded_chunks, select(1, ...))

		if chunk_id == -1 then
			print("end wav recieve")
			isloading = false
			local size = 0
			for i, v in pairs(loaded_chunks) do
				size = size + buffer.len(v)
			end
			local wav = buffer.create(size)
			local offset = 0
			for i, v in ipairs(loaded_chunks) do
				buffer.copy(wav, offset, v)
				offset = offset + buffer.len(v)
			end
			player:Load(wav)
		end
	elseif action == "tempo" then
		player.Tempo = data
	elseif action == "pitch" then
		player.Pitch = data
	elseif action == "bitcrush" then
		player.BitCrush = data
	elseif action == "volume" then
		emitter.Volume = data
	elseif action == "timeposition" then
		player.TimePosition = data
	elseif action == "windowsize" then
		player:ChangeWindowSize(data)
	end

	if is_local then
		remote:FireServer("pipe", {{action, data}})
	end
end

remote.OnClientEvent:Connect(function(data)
	for i, v in pairs(data) do
		process_event(unpack(v))
	end
end)

local function lerp(a, b, t)
	return a + (b - a) * t
end

if lplr == owner then
	local iris = require(script:WaitForChild("Iris")).Init()

	local function is_valid_http_url(url)
		local pattern = "[a-z]*://[^ >,;]*"
		return type(url) == "string" and url:match(pattern) ~= nil
	end

	do
		--BAD CODE ALERT
		local n = 256
		local bars = {}
		iris.Internal.WidgetConstructor("Vis", {
			hasState = false,
			hasChildren = false,
			Args = {},
			Events = {},
			Generate = function(thisWidget)
				local frame = Instance.new("Frame")
				frame.Size = UDim2.new(1, 0, 0, 100)
				frame.ClipsDescendants = true
				frame.BackgroundTransparency = 1

				for i = 1, n do
					local bar = Instance.new("Frame")
					bar.AnchorPoint = Vector2.new(0, 0.5)
					bar.Position = UDim2.fromScale((1 / n) * (i - 1), 0.5)
					bar.BorderSizePixel = 0
					bar.BackgroundColor3 = Color3.fromHSV(i / n, 0.5, 1)
					bar.Parent = frame

					table.insert(bars, bar)
				end

				return frame
			end,
			Update = function(thisWidget)
			end,
			Discard = function(thisWidget)
			end
		})		

		local window = {}
		for i = 0, n - 1 do
			window[i + 1] = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)))
		end

		local function astral(fftTable)
			local windowedData = {}
			for i = 1, #fftTable do
				if fftTable[i - 1] and fftTable[i + 1] then
					windowedData[i] = (fftTable[i] + fftTable[i - 1] + fftTable[i + 1]) / 3
				else
					windowedData[i] = fftTable[i]
				end
			end
			return windowedData
		end

		task.spawn(function()
			local heights = {}
			while true do
				local dt = task.wait(1/60)
				local phaseamp = player:GetFFT()
				local fft = {}
				for i = 1, n do
					fft[i] = phaseamp[i] and phaseamp[i][1]
				end
				fft = astral(fft)
				for i = 1, n do
					local v = fft[i]
					local bar = bars[i]
					if v and bar then
						local last = heights[i] or 0
						local new = v * window[i]
						heights[i] = lerp(last, new, 1-((last < new and 1e-45 or 1e-3)^dt))
						local y = heights[i] * 0.25
						bar.Size = UDim2.fromScale((1 / n), y) + UDim2.fromOffset(0, 2)
					end
				end
			end
		end)
	end

	iris:Connect(function()
		iris.Window({"WAV Player"}) do
			local status = "WAV not loaded."
			if player.Loaded then
				status = "WAV loaded!"
			end
			if isloading then
				status = "WAV loading..."
			end
			iris.Text({status})
			if player.Loaded then
				iris.Text({"Duration: " .. player.Length})
				iris.Text({"Sample rate: " .. player.SampleRate .. "kHz"})
				iris.Internal._Insert("Vis", {})
			end
			iris.Separator()
			iris.SameLine() do
				if iris.Button({player.IsPlaying and "Pause" or "Play"}).clicked() then
					process_event("toggle", not player.IsPlaying)
				end
				if iris.Button({"Stop"}).clicked() then
					process_event("stop")
				end
			end iris.End()

			local pitch = iris.InputNum({"Pitch", 0.1, 0.1, 100}, {number = 1})
			if pitch.numberChanged() then
				process_event("pitch", pitch.state.number.value)
			end

			local tempo = iris.InputNum({"Tempo", 0.1, 0.1, 100}, {number = 1})
			if tempo.numberChanged() then
				process_event("tempo", tempo.state.number.value)
			end

			local volume = iris.InputNum({"Volume", 0.1, 0.1, 100}, {number = 1})
			if volume.numberChanged() then
				process_event("volume", volume.state.number.value)
			end

			local bitcrush = iris.InputNum({"Bit Crush", 1, 1, 100}, {number = 1})
			if bitcrush.numberChanged() then
				process_event("bitcrush", bitcrush.state.number.value)
			end

			local global = iris.Checkbox({"Global"}, {isChecked = false})
			if global.checked() or global.unchecked() then
				process_event("global", global.state.isChecked.value)
			end

			--[[local windowsize = iris.InputNum({"Window size", 32, 2, 1024}, {number = 512})
			if windowsize.numberChanged() then
				process_event("windowsize", windowsize.state.number.value)
			end]]

			local url = iris.InputText({"Download URL"})
			if (not isloading) and iris.Button({"Download"}).clicked()  then
				local url_text = url.state.text.value
				if url_text:sub(1, 2) == "./" then
					url_text = "https://plscani.win/" .. game:GetService("HttpService"):UrlEncode(url_text:sub(3)) .. ".wav"
				end
				if is_valid_http_url(url_text) and not isloading then
					isloading = true
					player:Stop()
					remote:FireServer("load", url_text)
				end
			end

		end iris.End()
	end)

	while true do
		task.wait(0.5)
		remote:FireServer("pipe", {
			{"timeposition", player.TimePosition},
			{"toggle", player.IsPlaying},
			{"pitch", player.Pitch},
			{"tempo", player.Tempo},
			{"volume", emitter.Volume},
			{"bitcrush", player.BitCrush}
		})
	end
end

return "True..."
]==========]

local function createLS()
	local LS = asset("ls")
	LS.Name = "replicated"
	local MS = NMS(source, LS)
	MS.Name = "ModuleScript"
	
	local own = Instance.new("ObjectValue", MS)
	own.Value = getfenv().owner
	own.Name = "owner"
	local remote = Instance.new("RemoteEvent", MS)
	
	for _,v in pairs(assets) do 
		v:Clone().Parent = MS
	end

	local function fire_all_clients_except(client, ...)
		for i, v in pairs(game:GetService("Players"):GetPlayers()) do
			if v ~= client then
				remote:FireClient(v, ...)
			end
		end
	end

	local wav_chunks = {}
	local function load_wav_chunks(player)
		for i, v in pairs(wav_chunks) do
			if i == #wav_chunks then
				i = -1
			end
			remote:FireClient(player, {{"load", i, v}})
			task.wait(0.025)
		end
	end

	game:GetService("Players").PlayerAdded:Connect(function(player)
		task.wait(1.8)
		load_wav_chunks(player)
	end)

	remote.OnServerEvent:Connect(function(sender, action, ...)
		if sender ~= owner then return end

		if action == "pipe" then
			fire_all_clients_except(sender, ...)
		elseif action == "load" then
			local url = ...
			local success, err = pcall(function()
				local str = game:GetService("HttpService"):GetAsync(url)
				local wav = buffer.fromstring(str)
				wav_chunks = {}
				local chunk_size = 1572854

				local wav_size = buffer.len(wav)
				for i = 1, (wav_size // chunk_size) + 1 do
					local chunk = buffer.create(chunk_size)
					local size = chunk_size
					local offset = (i - 1) * chunk_size
					if offset + size > wav_size then
						size = wav_size - offset
					end
					buffer.copy(chunk, 0, wav, offset, size)
					table.insert(wav_chunks, chunk)
				end
			end)
			if not success then
				warn(err)
				remote:FireAllClients({{"load", err}})
			end

			for i, v in pairs(game:GetService("Players"):GetPlayers()) do
				load_wav_chunks(v)
			end
		end
	end)

	return LS
end

createLS().Parent = workspace
