Require "import"

-- ==========================================
-- ANDROID CORE & UI BINDINGS CONTAINER
-- ==========================================
local BTP_Core = {
  LinearLayout = luajava.bindClass("android.widget.LinearLayout"),
  TextView = luajava.bindClass("android.widget.TextView"),
  EditText = luajava.bindClass("android.widget.EditText"),
  Button = luajava.bindClass("android.widget.Button"),
  View = luajava.bindClass("android.view.View"),
  Color = luajava.bindClass("android.graphics.Color"),
  Gravity = luajava.bindClass("android.view.Gravity"),
  ListView = luajava.bindClass("android.widget.ListView"),
  ArrayAdapter = luajava.bindClass("android.widget.ArrayAdapter"),
  Toast = luajava.bindClass("android.widget.Toast"),
  Context = luajava.bindClass("android.content.Context"),
  Ticker = luajava.bindClass("com.androlua.Ticker"),
  Http = luajava.bindClass("com.androlua.Http"),
  AlertDialog = luajava.bindClass("android.app.AlertDialog"),
  DialogInterface = luajava.bindClass("android.content.DialogInterface"),
  TextToSpeech = luajava.bindClass("android.speech.tts.TextToSpeech"),
  Intent = luajava.bindClass("android.content.Intent"),
  Uri = luajava.bindClass("android.net.Uri"),
  KeyEvent = luajava.bindClass("android.view.KeyEvent"),
  CheckBox = luajava.bindClass("android.widget.CheckBox"),
  Locale = luajava.bindClass("java.util.Locale"),
  MediaPlayer = luajava.bindClass("android.media.MediaPlayer"),
  MediaRecorder = luajava.bindClass("android.media.MediaRecorder"),
  RingtoneManager = luajava.bindClass("android.media.RingtoneManager"),
  SeekBar = luajava.bindClass("android.widget.SeekBar"),
  File = luajava.bindClass("java.io.File"),
  FileOutputStream = luajava.bindClass("java.io.FileOutputStream"),
  FileInputStream = luajava.bindClass("java.io.FileInputStream"),
  Runnable = luajava.bindClass("java.lang.Runnable"),
  Handler = luajava.bindClass("android.os.Handler"),
  Looper = luajava.bindClass("android.os.Looper")
}

local CURRENT_VERSION = "1.5"
local BASE_URL = "https://ibrahim-6e4a3-default-rtdb.firebaseio.com/"
local STORAGE_BUCKET = "ibrahim-6e4a3.appspot.com"
local CHAT_URL = BASE_URL .. "chat.json"
local USERS_URL = BASE_URL .. "registered_users/"
local CUSTOM_ROOMS_URL = BASE_URL .. "custom_rooms/"
local ACTIVE_STATUS_URL = BASE_URL .. "status/"
local REQUESTS_URL = BASE_URL .. "room_requests/"

local VERSION_URL = "https://raw.githubusercontent.com/blindpowerhub-hash/ibrahim-ansari/main/version.txt"
local NOTE_URL = "https://raw.githubusercontent.com/blindpowerhub-hash/ibrahim-ansari/main/note.txt"
local UPDATE_FILE_URL = "https://raw.githubusercontent.com/blindpowerhub-hash/ibrahim-ansari/main/update.lua"

local currentUser = { name = "", secureCode = "" }
local sp = activity.getSharedPreferences("BTPChatConfig", BTP_Core.Context.MODE_PRIVATE)
local savedName = sp.getString("username", "")
local savedCode = sp.getString("secure_code", "")

local tickers = {} 
local currentActiveRoom = "Public Chatroom"
local currentRoomCreator = ""
local inChatroomScope = false 

-- Forward Declarations & Cache Architecture
local syncLiveChatEngine = nil
local rawKeysMapping = {}
local ttsEngine = nil
local announcedMessages = {}
local knownMutedUsers = {}
local knownBlockedUsers = {}
local spokenNotificationsCache = {}

-- Audio & Voice Message Advanced States
local appMediaRecorder = nil
local activeRecordingPath = ""
local isCurrentlyRecording = false
local currentActiveMediaPlayer = nil
local activeAudioSeekBarTicker = nil

local THEME_BG = "#121212"
local THEME_ACCENT = "#2979FF"
local THEME_SUCCESS = "#00E676"
local THEME_DANGER = "#E53935"

local showLoginWindow, showDashboardWindow, openPublicChatroom, openBTPSettings, triggerExitVerification, checkApplicationUpdates

-- ==========================================
-- UI THREAD HELPER TO PREVENT CRASHES
-- ==========================================
local function RunUI(action)
  activity.runOnUiThread(BTP_Core.Runnable{
    run = action
  })
end

-- ==========================================
-- ACCESSIBILITY TALKBACK UTILITIES
-- ==========================================
local function applyAccessibilityNode(view, description, isHeader)
  if not view then return end
  local success, err = pcall(function()
    view.setContentDescription(description)
    view.setFocusable(true)
    if isHeader and luajava.bindClass("android.os.Build").VERSION.SDK_INT >= 28 then
      view.setAccessibilityHeading(true)
    end
  end)
end

local function announceViaTalkBack(text)
  if not text then return end
  local success, err = pcall(function()
    local manager = activity.getSystemService(BTP_Core.Context.ACCESSIBILITY_SERVICE)
    if manager and manager.isEnabled() then
      local event = luajava.bindClass("android.view.accessibility.AccessibilityEvent").obtain()
      event.setEventType(luajava.bindClass("android.view.accessibility.AccessibilityEvent").TYPE_ANNOUNCEMENT)
      event.getText().add(text)
      manager.sendAccessibilityEvent(event)
    end
  end)
end

-- ==========================================
-- INITIALIZE TEXT-TO-SPEECH ENGINE
-- ==========================================
local ttsSuccess, ttsErr = pcall(function()
  ttsEngine = BTP_Core.TextToSpeech(activity, BTP_Core.TextToSpeech.OnInitListener{
    onInit = function(status)
      if status == BTP_Core.TextToSpeech.SUCCESS then
        ttsEngine.setLanguage(BTP_Core.Locale.US)
        local savedPitch = sp.getFloat("tts_pitch", 1.0)
        local savedSpeed = sp.getFloat("tts_speed", 1.0)
        ttsEngine.setPitch(savedPitch)
        ttsEngine.setSpeechRate(savedSpeed)
      end
    end
  })
end)
if not ttsSuccess then
    BTP_Core.Toast.makeText(activity, "TTS Init Error: " .. tostring(ttsErr), BTP_Core.Toast.LENGTH_LONG).show()
end

local function triggerSpeech(text)
  if not text then return end
  if spokenNotificationsCache[text] and (os.time() - spokenNotificationsCache[text] < 3) then
    return 
  end
  spokenNotificationsCache[text] = os.time()
  
  if ttsEngine and sp.getBoolean("tts_enabled", true) then
    local currentPitch = sp.getFloat("tts_pitch", 1.0)
    local currentSpeed = sp.getFloat("tts_speed", 1.0)
    ttsEngine.setPitch(currentPitch)
    ttsEngine.setSpeechRate(currentSpeed)
    ttsEngine.speak(text, BTP_Core.TextToSpeech.QUEUE_FLUSH, nil)
  end
  announceViaTalkBack(text)
end

-- ==========================================
-- SAFE STRING SANITIZATION ENGINE
-- ==========================================
local function cleanFirebaseKey(input)
  if not input then return "" end
  -- FIX: Added %s to regex to replace spaces with underscores, preventing URL crashes
  return tostring(input):gsub("[%.#%$%[%]%s]", "_")
end

local function escapeJsonPayload(input)
  if not input then return "" end
  return tostring(input):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
end

local function formatUserName(rawName)
  if not rawName then return "" end
  local cleaned = tostring(rawName):gsub("^%s*(.-)%s*$", "%1")
  return cleaned
end

-- ==========================================
-- AUDIO ROUTINES
-- ==========================================
local function playAudioAsset(filename)
  local success, err = pcall(function()
    local mp = BTP_Core.MediaPlayer()
    local notifUri = BTP_Core.RingtoneManager.getDefaultUri(BTP_Core.RingtoneManager.TYPE_NOTIFICATION)
    mp.setDataSource(activity, notifUri)
    mp.prepare()
    mp.start()
    mp.setOnCompletionListener(BTP_Core.MediaPlayer.OnCompletionListener{
      onCompletion = function(player)
        player.release()
      end
    })
  end)
end

local function cleanActivePlaybackResources()
  if activeAudioSeekBarTicker then
    activeAudioSeekBarTicker.stop()
    activeAudioSeekBarTicker = nil
  end
  if currentActiveMediaPlayer then
    pcall(function()
      if currentActiveMediaPlayer.isPlaying() then
        currentActiveMediaPlayer.stop()
      end
      currentActiveMediaPlayer.release()
    end)
    currentActiveMediaPlayer = nil
  end
end

local function playDirectAudioFile(absolutePathOrUrl)
  cleanActivePlaybackResources()
  
  local diag = BTP_Core.AlertDialog.Builder(activity)
  diag.setTitle("Voice Player Control")
  
  local container = BTP_Core.LinearLayout(activity)
  container.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  container.setPadding(40, 30, 40, 30)
  
  local statusLabel = BTP_Core.TextView(activity)
  statusLabel.setText("Status: Buffering digital streams...")
  statusLabel.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  container.addView(statusLabel)
  
  local sb = BTP_Core.SeekBar(activity)
  container.addView(sb)
  
  local timeLabel = BTP_Core.TextView(activity)
  timeLabel.setText("Duration: --:-- / --:--")
  timeLabel.setTextColor(BTP_Core.Color.parseColor("#A8A8A8"))
  container.addView(timeLabel)

  local controlPanel = BTP_Core.LinearLayout(activity)
  controlPanel.setOrientation(BTP_Core.LinearLayout.HORIZONTAL)
  controlPanel.setGravity(BTP_Core.Gravity.CENTER)
  
  local btnPause = BTP_Core.Button(activity)
  btnPause.setText("Pause")
  controlPanel.addView(btnPause)
  
  local btnResume = BTP_Core.Button(activity)
  btnResume.setText("Resume")
  controlPanel.addView(btnResume)
  
  container.addView(controlPanel)
  diag.setView(container)
  diag.setPositiveButton("Close", BTP_Core.DialogInterface.OnClickListener{
    onClick = function(d, w)
      cleanActivePlaybackResources()
    end
  })
  
  local activeDialogInstance = diag.show()
  
  local success, err = pcall(function()
    currentActiveMediaPlayer = BTP_Core.MediaPlayer()
    
    if absolutePathOrUrl:find("^http") then
      currentActiveMediaPlayer.setDataSource(activity, BTP_Core.Uri.parse(absolutePathOrUrl))
    else
      currentActiveMediaPlayer.setDataSource(absolutePathOrUrl)
    end
    
    currentActiveMediaPlayer.prepareAsync()
    
    currentActiveMediaPlayer.setOnPreparedListener(BTP_Core.MediaPlayer.OnPreparedListener{
      onPrepared = function(mp)
        RunUI(function()
          statusLabel.setText("Status: Playing track sequence...")
          mp.start()
          local maxDuration = mp.getDuration()
          sb.setMax(maxDuration)
        end)
        
        activeAudioSeekBarTicker = BTP_Core.Ticker()
        activeAudioSeekBarTicker.Period = 300
        activeAudioSeekBarTicker.onTick = function()
          local tSuccess, tErr = pcall(function()
            if currentActiveMediaPlayer and currentActiveMediaPlayer.isPlaying() then
              local currentPos = currentActiveMediaPlayer.getCurrentPosition()
              RunUI(function()
                sb.setProgress(currentPos)
                local rem = maxDuration - currentPos
                
                local curSec = math.floor((currentPos / 1000) % 60)
                local curMin = math.floor((currentPos / 1000) / 60)
                local remSec = math.floor((rem / 1000) % 60)
                local remMin = math.floor((rem / 1000) / 60)
                
                timeLabel.setText(string.format("Duration: %02d:%02d / Remaining: %02d:%02d", curMin, curSec, remMin, remSec))
              end)
            end
          end)
        end
        activeAudioSeekBarTicker.start()
      end
    })
    
    currentActiveMediaPlayer.setOnCompletionListener(BTP_Core.MediaPlayer.OnCompletionListener{
      onCompletion = function(mp)
        RunUI(function()
          statusLabel.setText("Status: Playback completed.")
          sb.setProgress(mp.getDuration())
          cleanActivePlaybackResources()
          activeDialogInstance.dismiss()
        end)
      end
    })
    
    currentActiveMediaPlayer.setOnErrorListener(BTP_Core.MediaPlayer.OnErrorListener{
      onError = function(mp, what, extra)
        RunUI(function()
          statusLabel.setText("Status: Dynamic network streaming dropped.")
          cleanActivePlaybackResources()
        end)
        return true
      end
    })
    
    btnPause.onClick = function()
      if currentActiveMediaPlayer and currentActiveMediaPlayer.isPlaying() then
        currentActiveMediaPlayer.pause()
        statusLabel.setText("Status: Paused.")
      end
    end
    
    btnResume.onClick = function()
      if currentActiveMediaPlayer then
        currentActiveMediaPlayer.start()
        statusLabel.setText("Status: Playing track sequence...")
      end
    end
    
    sb.setOnSeekBarChangeListener{
      onProgressChanged = function(s, progress, fromUser)
        if fromUser and currentActiveMediaPlayer then
          currentActiveMediaPlayer.seekTo(progress)
        end
      end
    }
  end)
  if not success then
    BTP_Core.Toast.makeText(activity, "Player Error: " .. tostring(err), BTP_Core.Toast.LENGTH_LONG).show()
  end
end

-- ==========================================
-- REAL-TIME PRESENCE SYSTEM PIPELINE
-- ==========================================
local function updateMyPresence(roomName, state)
  if not roomName or currentUser.name == "" then return end
  local safeNameNode = cleanFirebaseKey(currentUser.name)
  local safeRoomNode = cleanFirebaseKey(roomName)
  local targetUrl = ACTIVE_STATUS_URL .. safeRoomNode .. "/" .. safeNameNode .. ".json"
  
  if state == "offline" then
    BTP_Core.Http.delete(targetUrl, function(c, b) end)
  else
    local payload = string.format('{"last_seen":%d,"state":"%s"}', os.time(), state)
    BTP_Core.Http.put(targetUrl, payload, function(c, b) end)
  end
end

function onKeyDown(keyCode, event)
  if keyCode == BTP_Core.KeyEvent.KEYCODE_BACK then
    if inChatroomScope then triggerExitVerification() return true end
  end
  return false
end

-- ==========================================
-- AUTOMATED RESILIENT UPDATE MATRIX
-- ==========================================
checkApplicationUpdates = function(silent)
  BTP_Core.Http.get(VERSION_URL, function(vCode, vBody)
    if vCode == 200 and vBody then
      local latestVersion = vBody:gsub("^%s*(.-)%s*$", "%1")
      if latestVersion ~= CURRENT_VERSION then
        BTP_Core.Http.get(NOTE_URL, function(nCode, nBody)
          local changeLog = (nCode == 200 and nBody) and nBody or "Critical version update configured."
          
          RunUI(function()
              local updateDialog = BTP_Core.AlertDialog.Builder(activity)
              updateDialog.setTitle("Update Available (v" .. latestVersion .. ")")
              updateDialog.setMessage(changeLog)
              updateDialog.setCancelable(false)
              
              updateDialog.setPositiveButton("Update", BTP_Core.DialogInterface.OnClickListener{
                onClick = function(d, w)
                  BTP_Core.Toast.makeText(activity, "Updating please wait...", BTP_Core.Toast.LENGTH_SHORT).show()
                  BTP_Core.Http.get(UPDATE_FILE_URL, function(uCode, uBody)
                    if uCode == 200 and uBody and uBody:find("require") then
                      local s, e = pcall(function()
                        local destinationPath = activity.getLuaDir() .. "/main.lua"
                        local file = BTP_Core.File(destinationPath)
                        local out = BTP_Core.FileOutputStream(file)
                        out.write(luajava.toBytes(uBody))
                        out.close()
                        
                        RunUI(function()
                          local successDiag = BTP_Core.AlertDialog.Builder(activity)
                          successDiag.setTitle("Update Complete")
                          successDiag.setMessage("Application framework compiled successfully!\n\nChangelog Details:\n" .. changeLog)
                          successDiag.setCancelable(false)
                          successDiag.setPositiveButton("OK", BTP_Core.DialogInterface.OnClickListener{
                            onClick = function(d2, w2)
                              activity.recreate()
                            end
                          })
                          successDiag.show()
                        end)
                      end)
                      if not s then
                          RunUI(function() BTP_Core.Toast.makeText(activity, "Write Error: " .. tostring(e), 1).show() end)
                      end
                    else
                      RunUI(function() BTP_Core.Toast.makeText(activity, "Update deployment failed.", BTP_Core.Toast.LENGTH_SHORT).show() end)
                    end
                  end)
                end
              })
              updateDialog.setNegativeButton("Later", nil)
              updateDialog.show()
          end)
        end)
      else
        if not silent then
          RunUI(function()
              local noUpdateDiag = BTP_Core.AlertDialog.Builder(activity)
              noUpdateDiag.setTitle("Up to date")
              noUpdateDiag.setMessage("Are you using the latest version.")
              noUpdateDiag.setPositiveButton("OK", nil)
              noUpdateDiag.show()
          end)
        end
      end
    else
      if not silent then
        RunUI(function() BTP_Core.Toast.makeText(activity, "Unable to reach update server.", BTP_Core.Toast.LENGTH_SHORT).show() end)
      end
    end
  end)
end

-- ==========================================
-- REGISTRATION SETUP ROUTINE
-- ==========================================
showLoginWindow = function()
  inChatroomScope = false
  local mainLayout = BTP_Core.LinearLayout(activity)
  mainLayout.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  mainLayout.setBackgroundColor(BTP_Core.Color.parseColor(THEME_BG))
  mainLayout.setPadding(50, 50, 50, 50)
  mainLayout.setGravity(BTP_Core.Gravity.CENTER)

  local welcomeText = BTP_Core.TextView(activity)
  welcomeText.setText("BTP Chat Friend")
  welcomeText.setTextSize(26)
  welcomeText.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  welcomeText.setPadding(0, 0, 0, 40)
  applyAccessibilityNode(welcomeText, "BTP Chat Friend", true)
  mainLayout.addView(welcomeText)

  local nameInput = BTP_Core.EditText(activity)
  nameInput.setHint("Enter username...")
  nameInput.setHintTextColor(BTP_Core.Color.parseColor("#777777"))
  nameInput.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  nameInput.setMinimumWidth(650)
  applyAccessibilityNode(nameInput, "Enter username input field")
  mainLayout.addView(nameInput)

  local loginBtn = BTP_Core.Button(activity)
  loginBtn.setText("Login")
  loginBtn.setBackgroundColor(BTP_Core.Color.parseColor(THEME_SUCCESS))
  loginBtn.setTextColor(BTP_Core.Color.parseColor("#000000"))
  applyAccessibilityNode(loginBtn, "Login")
  mainLayout.addView(loginBtn)

  activity.setContentView(mainLayout)

  loginBtn.onClick = function()
    local inputName = formatUserName(tostring(nameInput.getText()))
    if inputName == "" then BTP_Core.Toast.makeText(activity, "Username cannot be blank!", BTP_Core.Toast.LENGTH_SHORT).show() return end

    local safeNameNode = cleanFirebaseKey(inputName)
    local lowerName = inputName:lower()
    
    -- FIX: Admin Login ab Database mein Real-Time sync karega 
    if lowerName == "ibrahim" or lowerName == "ibrahim ansari" then
       currentUser.name = "Ibrahim Ansari"
       currentUser.secureCode = "0000"
       sp.edit().putString("username", currentUser.name).putString("secure_code", currentUser.secureCode).commit()
       
       local safeAdminNode = cleanFirebaseKey(currentUser.name)
       local adminPayload = string.format('{"name":"%s","code":"0000","session":"active"}', escapeJsonPayload(currentUser.name))
       BTP_Core.Http.put(USERS_URL .. safeAdminNode .. ".json", adminPayload, function(c, b)
         RunUI(function() showDashboardWindow() end)
       end)
       return
    end

    if lowerName:find("verified") or lowerName:find("✓") or lowerName:find("official") then
       BTP_Core.Toast.makeText(activity, "Error: Yeh naam galat hai. Status use nahi kar sakte.", BTP_Core.Toast.LENGTH_SHORT).show()
       return
    end

    BTP_Core.Http.get(USERS_URL .. safeNameNode .. ".json", function(code, body)
      RunUI(function()
        if code == 200 and body and body ~= "null" then
          local serverCode = body:match('"code":"([^"]+)"')
          local currentActiveSession = body:match('"session":"([^"]+)"')
          
          if currentActiveSession == "active" then
             BTP_Core.Toast.makeText(activity, "Error: Duplicate login detected.", BTP_Core.Toast.LENGTH_LONG).show()
             return
          end

          local verificationDialog = BTP_Core.AlertDialog.Builder(activity)
          verificationDialog.setTitle("Enter PIN")
          local codeInput = BTP_Core.EditText(activity)
          codeInput.setHint("Enter 4-digit PIN...")
          verificationDialog.setView(codeInput)
          verificationDialog.setPositiveButton("Verify", BTP_Core.DialogInterface.OnClickListener{
            onClick = function(d, w)
              if tostring(codeInput.getText()) == serverCode then
                currentUser.name = inputName
                currentUser.secureCode = serverCode
                sp.edit().putString("username", currentUser.name).putString("secure_code", currentUser.secureCode).commit()
                
                local updateSessionUrl = USERS_URL .. safeNameNode .. "/session.json"
                BTP_Core.Http.put(updateSessionUrl, '"active"', function(c, b)
                  RunUI(function() showDashboardWindow() end)
                end)
              else
                BTP_Core.Toast.makeText(activity, "Incorrect PIN!", BTP_Core.Toast.LENGTH_SHORT).show()
              end
            end
          })
          verificationDialog.show()
        else
          local generatedCode = tostring(math.random(1000, 9999))
          local userPayload = string.format('{"name":"%s","code":"%s","session":"active"}', escapeJsonPayload(inputName), generatedCode)
          BTP_Core.Http.put(USERS_URL .. safeNameNode .. ".json", userPayload, function(c, b)
            RunUI(function()
              currentUser.name = inputName
              currentUser.secureCode = generatedCode
              sp.edit().putString("username", currentUser.name).putString("secure_code", currentUser.secureCode).commit()
              showDashboardWindow()
            end)
          end)
        end
      end)
    end)
  end
  checkApplicationUpdates(true)
end

-- ==========================================
-- DASHBOARD CONSOLE MANAGEMENT
-- ==========================================
showDashboardWindow = function()
  inChatroomScope = false
  if tickers.Dashboard then tickers.Dashboard.stop() end
  
  if currentUser.name == "" then
    currentUser.name = formatUserName(sp.getString("username", ""))
    currentUser.secureCode = sp.getString("secure_code", "")
  end

  local dashboardLayout = BTP_Core.LinearLayout(activity)
  dashboardLayout.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  dashboardLayout.setBackgroundColor(BTP_Core.Color.parseColor(THEME_BG))
  dashboardLayout.setPadding(40, 40, 40, 40)

  local titleView = BTP_Core.TextView(activity)
  titleView.setText("BTP Chat Friend")
  titleView.setTextSize(22)
  titleView.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  applyAccessibilityNode(titleView, "BTP Chat Friend", true)
  dashboardLayout.addView(titleView)

  local devView = BTP_Core.TextView(activity)
  devView.setText("Developed by Ibrahim Ansari")
  devView.setTextSize(14)
  devView.setTextColor(BTP_Core.Color.parseColor("#A8A8A8"))
  dashboardLayout.addView(devView)

  local displayHandle = currentUser.name
  if currentUser.name == "Ibrahim Ansari" then
     displayHandle = "Ibrahim Ansari [Verified]"
  end

  local userDisplayView = BTP_Core.TextView(activity)
  userDisplayView.setText("User: " .. displayHandle)
  userDisplayView.setTextSize(14)
  userDisplayView.setTextColor(BTP_Core.Color.parseColor(THEME_ACCENT))
  userDisplayView.setPadding(0, 5, 0, 30)
  dashboardLayout.addView(userDisplayView)

  local btnEnterChat = BTP_Core.Button(activity)
  btnEnterChat.setText("Enter Public Lobby")
  btnEnterChat.setBackgroundColor(BTP_Core.Color.parseColor(THEME_ACCENT))
  btnEnterChat.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  applyAccessibilityNode(btnEnterChat, "Enter Public Lobby")
  dashboardLayout.addView(btnEnterChat)

  local btnCreateRoom = BTP_Core.Button(activity)
  btnCreateRoom.setText("Create Private Room")
  btnCreateRoom.setBackgroundColor(BTP_Core.Color.parseColor("#E040FB"))
  btnCreateRoom.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  local layoutP = BTP_Core.LinearLayout.LayoutParams(BTP_Core.LinearLayout.LayoutParams.MATCH_PARENT, BTP_Core.LinearLayout.LayoutParams.WRAP_CONTENT)
  layoutP.setMargins(0, 20, 0, 0)
  btnCreateRoom.setLayoutParams(layoutP)
  applyAccessibilityNode(btnCreateRoom, "Create Private Room")
  dashboardLayout.addView(btnCreateRoom)

  local activeRoomsLabel = BTP_Core.TextView(activity)
  activeRoomsLabel.setText("Available Custom Rooms: 0")
  activeRoomsLabel.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  activeRoomsLabel.setPadding(0, 20, 0, 10)
  dashboardLayout.addView(activeRoomsLabel)

  local customRoomList = BTP_Core.ListView(activity)
  local roomAdapter = BTP_Core.ArrayAdapter(activity, android.R.layout.simple_list_item_1)
  customRoomList.setAdapter(roomAdapter)
  customRoomList.setLayoutParams(BTP_Core.LinearLayout.LayoutParams(BTP_Core.LinearLayout.LayoutParams.MATCH_PARENT, 400))
  dashboardLayout.addView(customRoomList)

  local btnSettings = BTP_Core.Button(activity)
  btnSettings.setText("BTP Settings")
  btnSettings.setBackgroundColor(BTP_Core.Color.parseColor("#424242"))
  btnSettings.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnSettings.setLayoutParams(layoutP)
  applyAccessibilityNode(btnSettings, "BTP Settings")
  dashboardLayout.addView(btnSettings)

  activity.setContentView(dashboardLayout)

  local rawRoomsMapping = {}
  
  local function syncCustomRooms()
    BTP_Core.Http.get(CUSTOM_ROOMS_URL .. ".json", function(code, body)
      RunUI(function()
        if code == 200 and body and body ~= "null" then
          roomAdapter.clear()
          rawRoomsMapping = {}
          local count = 0
          local currentTime = os.time()
          
          BTP_Core.Http.get(ACTIVE_STATUS_URL .. ".json", function(sCode, sBody)
            RunUI(function()
              local statusData = {}
              if sCode == 200 and sBody and sBody ~= "null" then
                for rNode, rUsers in sBody:gmatch('"([^"]+)":({[^}]+})') do
                  local uCount = 0
                  for _, uTimestamp in rUsers:gmatch('"([^"]+)":{"last_seen":(%-?%d+)}') do 
                    if (currentTime - tonumber(uTimestamp)) < 15 then
                       uCount = uCount + 1 
                    end
                  end
                  statusData[rNode] = uCount
                end
              end

              for roomNode, roomData in body:gmatch('"([^"]+)":({[^}]+})') do
                local roomName = roomData:match('"name":"([^"]+)"')
                local creator = roomData:match('"creator":"([^"]+)"')
                local lastActive = roomData:match('"last_active":(%d+)')
                
                if roomName then
                  local safeNode = cleanFirebaseKey(roomName)
                  local activeCount = statusData[safeNode] or 0
                  local roomTime = lastActive and tonumber(lastActive) or currentTime
                  
                  if (currentTime - roomTime > 1200) and activeCount == 0 then
                     BTP_Core.Http.delete(CUSTOM_ROOMS_URL .. roomNode .. ".json", function(c1, b1)
                       BTP_Core.Http.delete(BASE_URL .. "rooms/" .. roomNode .. ".json", function(c2, b2) end)
                     end)
                  else
                    roomAdapter.add(string.format("%s (Active: %d)", roomName, activeCount))
                    table.insert(rawRoomsMapping, {node = roomNode, name = roomName, creator = creator})
                    count = count + 1
                  end
                end
              end
              activeRoomsLabel.setText("Available Custom Rooms: " .. tostring(count))
            end)
          end)
        else
          roomAdapter.clear()
          activeRoomsLabel.setText("Available Custom Rooms: 0")
        end
      end)
    end)
  end

  tickers.Dashboard = BTP_Core.Ticker()
  tickers.Dashboard.Period = 4000
  tickers.Dashboard.onTick = function() syncCustomRooms() end
  tickers.Dashboard.start()
  syncCustomRooms()

  btnEnterChat.onClick = function()
    currentActiveRoom = "Public Chatroom"
    currentRoomCreator = ""
    openPublicChatroom()
  end

  btnCreateRoom.onClick = function()
    local container = BTP_Core.LinearLayout(activity)
    local inputField = BTP_Core.EditText(activity)
    inputField.setHint("Enter room name...")
    container.setPadding(30, 10, 30, 10)
    container.addView(inputField)
    local diag = BTP_Core.AlertDialog.Builder(activity)
    diag.setTitle("Create Room")
    diag.setView(container)
    diag.setPositiveButton("Create", BTP_Core.DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        local roomTitle = tostring(inputField.getText()):gsub("^%s*(.-)%s*$", "%1")
        if roomTitle ~= "" then
          local safeRoomNode = cleanFirebaseKey(roomTitle)
          local payload = string.format('{"name":"%s","creator":"%s","last_active":%d}', escapeJsonPayload(roomTitle), escapeJsonPayload(currentUser.name), os.time())
          BTP_Core.Http.put(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", payload, function(c, b)
            RunUI(function()
              currentActiveRoom = roomTitle
              currentRoomCreator = currentUser.name
              openPublicChatroom()
            end)
          end)
        end
      end
    })
    diag.show()
  end

  customRoomList.onItemClick = function(parent, view, position, id)
    local selectedRoom = rawRoomsMapping[position + 1]
    if selectedRoom then
      currentRoomCreator = selectedRoom.creator
      currentActiveRoom = selectedRoom.name
      
      if selectedRoom.creator ~= currentUser.name then
        local safeRoomNode = cleanFirebaseKey(selectedRoom.name)
        local safeMe = cleanFirebaseKey(currentUser.name)
        local reqPayload = string.format('{"requester":"%s","status":"pending","time":%d}', escapeJsonPayload(currentUser.name), os.time())
        BTP_Core.Http.put(REQUESTS_URL .. safeRoomNode .. "/" .. safeMe .. ".json", reqPayload, function(c,b) end)
      end
      openPublicChatroom()
    end
  end

  customRoomList.onItemLongClick = function(parent, view, position, id)
    local selectedRoom = rawRoomsMapping[position + 1]
    if not selectedRoom then return true end
    
    if selectedRoom.creator == currentUser.name then
      local diag = BTP_Core.AlertDialog.Builder(activity)
      diag.setTitle("Delete Room")
      diag.setMessage("Are you sure you want to delete this room entirely from server?")
      diag.setPositiveButton("Delete", BTP_Core.DialogInterface.OnClickListener{
        onClick = function(dialog, which)
          local safeRoomNode = cleanFirebaseKey(selectedRoom.name)
          BTP_Core.Http.delete(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", function(c, b)
            BTP_Core.Http.delete(BASE_URL .. "rooms/" .. safeRoomNode .. ".json", function(c2, b2)
              RunUI(function()
                BTP_Core.Toast.makeText(activity, "Room and history purged from server", BTP_Core.Toast.LENGTH_SHORT).show()
                syncCustomRooms()
              end)
            end)
          end)
        end
      })
      diag.setNegativeButton("Cancel", nil)
      diag.show()
    else
      BTP_Core.Toast.makeText(activity, "Only the room owner can delete this from the dashboard!", BTP_Core.Toast.LENGTH_SHORT).show()
    end
    return true
  end

  btnSettings.onClick = function() openBTPSettings() end
end

-- ==========================================
-- INTERACTION ROUTERS & SUBSYSTEM LISTENERS
-- ==========================================
openPublicChatroom = function()
  inChatroomScope = true
  announcedMessages = {}
  cleanActivePlaybackResources()
  if tickers.Dashboard then tickers.Dashboard.stop() end

  local chatroomLayout = BTP_Core.LinearLayout(activity)
  chatroomLayout.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  chatroomLayout.setBackgroundColor(BTP_Core.Color.parseColor("#161616"))
  chatroomLayout.setPadding(20, 20, 20, 20)

  local topBar = BTP_Core.LinearLayout(activity)
  topBar.setOrientation(BTP_Core.LinearLayout.HORIZONTAL)
  topBar.setGravity(BTP_Core.Gravity.CENTER_VERTICAL)
  topBar.setPadding(10, 10, 10, 20)
  
  local roomIndicator = BTP_Core.TextView(activity)
  roomIndicator.setText(currentActiveRoom)
  roomIndicator.setTextSize(18)
  roomIndicator.setTextColor(BTP_Core.Color.parseColor(THEME_ACCENT))
  roomIndicator.setLayoutParams(BTP_Core.LinearLayout.LayoutParams(0, BTP_Core.LinearLayout.LayoutParams.WRAP_CONTENT, 1.0))
  applyAccessibilityNode(roomIndicator, "Current room identifier", true)
  topBar.addView(roomIndicator)

  local statusDisplayLabel = BTP_Core.TextView(activity)
  statusDisplayLabel.setText("Active Users: Fetching...")
  statusDisplayLabel.setTextColor(BTP_Core.Color.parseColor("#A8A8A8"))
  statusDisplayLabel.setTextSize(13)
  statusDisplayLabel.setGravity(BTP_Core.Gravity.RIGHT)
  applyAccessibilityNode(statusDisplayLabel, "Active users tracking label")
  topBar.addView(statusDisplayLabel)
  
  chatroomLayout.addView(topBar)

  local safeRoomNode = cleanFirebaseKey(currentActiveRoom)
  local TARGET_ENDPOINT_URL = CHAT_URL
  if currentActiveRoom ~= "Public Chatroom" then
    TARGET_ENDPOINT_URL = BASE_URL .. "rooms/" .. safeRoomNode .. ".json"
  end

  local requestBarContainer = BTP_Core.LinearLayout(activity)
  requestBarContainer.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  requestBarContainer.setVisibility(BTP_Core.View.GONE)
  chatroomLayout.addView(requestBarContainer)

  local msgList = BTP_Core.ListView(activity)
  local adapter = BTP_Core.ArrayAdapter(activity, android.R.layout.simple_list_item_1)
  msgList.setAdapter(adapter)
  msgList.setLayoutParams(BTP_Core.LinearLayout.LayoutParams(BTP_Core.LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0))
  chatroomLayout.addView(msgList)

  local controlContainer = BTP_Core.LinearLayout(activity)
  controlContainer.setOrientation(BTP_Core.LinearLayout.VERTICAL)

  local bottomBar = BTP_Core.LinearLayout(activity)
  bottomBar.setOrientation(BTP_Core.LinearLayout.HORIZONTAL)
  
  local msgInput = BTP_Core.EditText(activity)
  msgInput.setHint("Type message...")
  msgInput.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  msgInput.setLayoutParams(BTP_Core.LinearLayout.LayoutParams(0, BTP_Core.LinearLayout.LayoutParams.WRAP_CONTENT, 1.0))
  applyAccessibilityNode(msgInput, "Message text box input")
  bottomBar.addView(msgInput)
  
  msgInput.setOnKeyListener(BTP_Core.View.OnKeyListener{
    onKey = function(v, keyCode, event)
      if tostring(msgInput.getText()) ~= "" then
        updateMyPresence(currentActiveRoom, "typing...")
      else
        updateMyPresence(currentActiveRoom, "active")
      end
      return false
    end
  })
  
  local btnSend = BTP_Core.Button(activity)
  btnSend.setText("Send")
  btnSend.setBackgroundColor(BTP_Core.Color.parseColor(THEME_SUCCESS))
  btnSend.setTextColor(BTP_Core.Color.parseColor("#000000"))
  applyAccessibilityNode(btnSend, "Send message")
  bottomBar.addView(btnSend)
  controlContainer.addView(bottomBar)

  local voicePanel = BTP_Core.LinearLayout(activity)
  voicePanel.setOrientation(BTP_Core.LinearLayout.HORIZONTAL)

  local btnRecordVoice = BTP_Core.Button(activity)
  btnRecordVoice.setText("Record")
  btnRecordVoice.setBackgroundColor(BTP_Core.Color.parseColor("#26A69A"))
  btnRecordVoice.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  applyAccessibilityNode(btnRecordVoice, "Record audio")
  voicePanel.addView(btnRecordVoice)

  local btnStopVoice = BTP_Core.Button(activity)
  btnStopVoice.setText("Stop")
  btnStopVoice.setBackgroundColor(BTP_Core.Color.parseColor(THEME_DANGER))
  btnStopVoice.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnStopVoice.setVisibility(BTP_Core.View.GONE)
  applyAccessibilityNode(btnStopVoice, "Stop audio record")
  voicePanel.addView(btnStopVoice)

  local btnCancelVoice = BTP_Core.Button(activity)
  btnCancelVoice.setText("Cancel Rec")
  btnCancelVoice.setBackgroundColor(BTP_Core.Color.parseColor("#757575"))
  btnCancelVoice.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnCancelVoice.setVisibility(BTP_Core.View.GONE)
  applyAccessibilityNode(btnCancelVoice, "Cancel current voice record")
  voicePanel.addView(btnCancelVoice)

  local btnSendVoice = BTP_Core.Button(activity)
  btnSendVoice.setText("Send VoiceMsg")
  btnSendVoice.setBackgroundColor(BTP_Core.Color.parseColor("#AB47BC"))
  btnSendVoice.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnSendVoice.setVisibility(BTP_Core.View.GONE)
  applyAccessibilityNode(btnSendVoice, "Send voice message")
  voicePanel.addView(btnSendVoice)

  controlContainer.addView(voicePanel)
  chatroomLayout.addView(controlContainer)
  activity.setContentView(chatroomLayout)

  updateMyPresence(currentActiveRoom, "active")

  triggerExitVerification = function()
    local exitDialog = BTP_Core.AlertDialog.Builder(activity)
    exitDialog.setTitle("Leave Room")
    exitDialog.setMessage("Are you sure you want to leave this room?")
    exitDialog.setPositiveButton("Leave", BTP_Core.DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        inChatroomScope = false
        if tickers.Fetch then tickers.Fetch.stop() end
        updateMyPresence(currentActiveRoom, "offline")
        if currentActiveRoom ~= "Public Chatroom" then
          local safeMe = cleanFirebaseKey(currentUser.name)
          BTP_Core.Http.delete(REQUESTS_URL .. safeRoomNode .. "/" .. safeMe .. ".json", function(c,b) end)
          local leftPayload = string.format('{"user":"System","message":"%s has left the chat matrix.","time":%d,"is_voice":false}', escapeJsonPayload(currentUser.name), os.time())
          BTP_Core.Http.post(TARGET_ENDPOINT_URL, leftPayload, function(c,b) end)
        end
        cleanActivePlaybackResources()
        BTP_Core.Toast.makeText(activity, "Left this room", BTP_Core.Toast.LENGTH_SHORT).show()
        showDashboardWindow()
      end
    })
    exitDialog.setNegativeButton("Cancel", nil)
    exitDialog.show()
  end

  statusDisplayLabel.setOnClickListener(BTP_Core.View.OnClickListener{
    onClick = function(v)
      local infoDialog = BTP_Core.AlertDialog.Builder(activity)
      infoDialog.setTitle("Room Info & Actions")
      
      local options = {"View Room Meta"}
      if currentActiveRoom ~= "Public Chatroom" and currentRoomCreator == currentUser.name then
        table.insert(options, "Delete Room Matrix")
        table.insert(options, "Rename Room")
      else
        table.insert(options, "Clear Chat (Admin Only)")
      end
      
      infoDialog.setItems(options, BTP_Core.DialogInterface.OnClickListener{
        onClick = function(d, idx)
          local choice = options[idx + 1]
          if choice == "View Room Meta" then
            BTP_Core.Toast.makeText(activity, "Room Target Node: " .. currentActiveRoom, BTP_Core.Toast.LENGTH_LONG).show()
          elseif choice == "Rename Room" then
            local reField = BTP_Core.EditText(activity)
            reField.setHint("Enter new room name...")
            local reDiag = BTP_Core.AlertDialog.Builder(activity)
            reDiag.setTitle("Rename Room")
            reDiag.setView(reField)
            reDiag.setPositiveButton("Save Changes", BTP_Core.DialogInterface.OnClickListener{
              onClick = function(d4, w4)
                local newName = tostring(reField.getText()):gsub("^%s*(.-)%s*$", "%1")
                if newName ~= "" then
                  local updateRen = string.format('{"name":"%s","creator":"%s","last_active":%d}', escapeJsonPayload(newName), escapeJsonPayload(currentRoomCreator), os.time())
                  BTP_Core.Http.put(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", updateRen, function(cRen, bRen)
                    RunUI(function()
                      currentActiveRoom = newName
                      BTP_Core.Toast.makeText(activity, "Room renamed successfully.", BTP_Core.Toast.LENGTH_SHORT).show()
                      activity.recreate()
                    end)
                  end)
                end
              end
            })
            reDiag.show()
          elseif choice == "Delete Room Matrix" then
            local confirmDiag = BTP_Core.AlertDialog.Builder(activity)
            confirmDiag.setTitle("Confirm Destruction")
            confirmDiag.setMessage("Delete this room and all historical audio data streams from database completely?")
            confirmDiag.setPositiveButton("Delete Forever", BTP_Core.DialogInterface.OnClickListener{
              onClick = function(d3, w3)
                inChatroomScope = false
                if tickers.Fetch then tickers.Fetch.stop() end
                updateMyPresence(currentActiveRoom, "offline")
                local delPayload = string.format('{"user":"System","message":"ROOM_DELETION_SIGNAL_EVENT","time":%d,"is_voice":false}', os.time())
                BTP_Core.Http.post(TARGET_ENDPOINT_URL, delPayload, function(cDel, bDel)
                  BTP_Core.Http.delete(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", function(c1, b1)
                    BTP_Core.Http.delete(BASE_URL .. "rooms/" .. safeRoomNode .. ".json", function(c2, b2)
                      RunUI(function()
                        triggerSpeech("Room deleted notification event executed.")
                        showDashboardWindow()
                      end)
                    end)
                  end)
                end)
              end
            })
            confirmDiag.setNegativeButton("Cancel", nil)
            confirmDiag.show()
          elseif choice == "Clear Chat (Admin Only)" then
            local lockInput = BTP_Core.EditText(activity)
            lockInput.setHint("Enter Admin Passcode...")
            
            local lockDiag = BTP_Core.AlertDialog.Builder(activity)
            lockDiag.setTitle("Security Clearance")
            lockDiag.setView(lockInput)
            lockDiag.setPositiveButton("Execute Clear", BTP_Core.DialogInterface.OnClickListener{
              onClick = function(d2, w2)
                if tostring(lockInput.getText()) == "321" then
                  BTP_Core.Http.delete(TARGET_ENDPOINT_URL, function(c, b)
                    RunUI(function()
                      BTP_Core.Toast.makeText(activity, "Chat history wiped globally", BTP_Core.Toast.LENGTH_SHORT).show()
                      if syncLiveChatEngine then syncLiveChatEngine() end
                    end)
                  end)
                else
                  BTP_Core.Toast.makeText(activity, "Access Denied!", BTP_Core.Toast.LENGTH_SHORT).show()
                end
              end
            })
            lockDiag.show()
          end
        end
      })
      infoDialog.show()
    end
  })

  btnRecordVoice.onClick = function()
    local success, err = pcall(function()
      activeRecordingPath = activity.getExternalCacheDir().getAbsolutePath() .. "/BTP_Audio_" .. os.time() .. ".3gp"
      appMediaRecorder = BTP_Core.MediaRecorder()
      appMediaRecorder.setAudioSource(BTP_Core.MediaRecorder.AudioSource.MIC)
      appMediaRecorder.setOutputFormat(BTP_Core.MediaRecorder.OutputFormat.THREE_GPP)
      appMediaRecorder.setAudioEncoder(BTP_Core.MediaRecorder.AudioEncoder.AMR_NB)
      appMediaRecorder.setOutputFile(activeRecordingPath)
      appMediaRecorder.prepare()
      appMediaRecorder.start()
      
      isCurrentlyRecording = true
      updateMyPresence(currentActiveRoom, "recording voice note")
      RunUI(function()
        btnRecordVoice.setVisibility(BTP_Core.View.GONE)
        btnStopVoice.setVisibility(BTP_Core.View.VISIBLE)
        btnCancelVoice.setVisibility(BTP_Core.View.VISIBLE)
        btnSendVoice.setVisibility(BTP_Core.View.GONE)
        BTP_Core.Toast.makeText(activity, "Voice note recording initialized...", BTP_Core.Toast.LENGTH_SHORT).show()
      end)
    end)
    if not success then
      RunUI(function() BTP_Core.Toast.makeText(activity, "Recorder Init Error: " .. tostring(err), BTP_Core.Toast.LENGTH_LONG).show() end)
    end
  end

  btnStopVoice.onClick = function()
    local success, err = pcall(function()
      if appMediaRecorder and isCurrentlyRecording then
        appMediaRecorder.stop()
        appMediaRecorder.release()
        appMediaRecorder = nil
        isCurrentlyRecording = false
        updateMyPresence(currentActiveRoom, "active")
        
        RunUI(function()
          btnStopVoice.setVisibility(BTP_Core.View.GONE)
          btnCancelVoice.setVisibility(BTP_Core.View.GONE)
          btnRecordVoice.setVisibility(BTP_Core.View.VISIBLE)
          btnSendVoice.setVisibility(BTP_Core.View.VISIBLE)
          BTP_Core.Toast.makeText(activity, "Recording completed successfully.", BTP_Core.Toast.LENGTH_SHORT).show()
        end)
      end
    end)
    if not success then
       RunUI(function() BTP_Core.Toast.makeText(activity, "Stop Error: " .. tostring(err), 1).show() end)
    end
  end

  btnCancelVoice.onClick = function()
    local success, err = pcall(function()
      if appMediaRecorder then
        appMediaRecorder.reset()
        appMediaRecorder.release()
        appMediaRecorder = nil
      end
      isCurrentlyRecording = false
      updateMyPresence(currentActiveRoom, "active")
      if activeRecordingPath ~= "" then
        BTP_Core.File(activeRecordingPath).delete()
        activeRecordingPath = ""
      end
      RunUI(function()
        btnStopVoice.setVisibility(BTP_Core.View.GONE)
        btnCancelVoice.setVisibility(BTP_Core.View.GONE)
        btnRecordVoice.setVisibility(BTP_Core.View.VISIBLE)
        btnSendVoice.setVisibility(BTP_Core.View.GONE)
        BTP_Core.Toast.makeText(activity, "Recording cancelled.", BTP_Core.Toast.LENGTH_SHORT).show()
      end)
    end)
    if not success then
      RunUI(function() BTP_Core.Toast.makeText(activity, "Cancel Error: " .. tostring(err), 1).show() end)
    end
  end

  btnSendVoice.onClick = function()
    if activeRecordingPath ~= "" then
      btnSendVoice.setEnabled(false)
      BTP_Core.Toast.makeText(activity, "Preparing audio bytes for cloud storage...", BTP_Core.Toast.LENGTH_SHORT).show()
      
      local audioFile = BTP_Core.File(activeRecordingPath)
      if not audioFile.exists() or audioFile.length() == 0 then
         BTP_Core.Toast.makeText(activity, "Error: Audio file is empty.", BTP_Core.Toast.LENGTH_SHORT).show()
         btnSendVoice.setEnabled(true)
         return
      end
      
      local fileLength = audioFile.length()
      local fileInputStream = BTP_Core.FileInputStream(audioFile)
      local byteBuffer = luajava.newArray("byte", fileLength)
      fileInputStream.read(byteBuffer)
      fileInputStream.close()

      local remoteFileName = "BTP_Audio_" .. os.time() .. "_" .. math.random(1000,9999) .. ".3gp"
      local storageEndpointUrl = "https://firebasestorage.googleapis.com/v0/b/" .. STORAGE_BUCKET .. "/o?name=" .. remoteFileName

      BTP_Core.Http.post(storageEndpointUrl, byteBuffer, function(uploadCode, uploadBody)
        RunUI(function()
          if uploadCode == 200 and uploadBody then
            local downloadToken = uploadBody:match('"downloadTokens":%s*"([^"]+)"')
            if not downloadToken then
              downloadToken = uploadBody:match('"downloadTokens":%s*%[%s*"([^"]+)"')
            end
            
            if downloadToken then
              local structuredDownloadUrl = "https://firebasestorage.googleapis.com/v0/b/" .. STORAGE_BUCKET .. "/o/" .. remoteFileName .. "?alt=media&token=" .. downloadToken
              
              playAudioAsset("message_send_voice")
              local voiceTextPayload = string.format("[Voice Message Path: %s]", structuredDownloadUrl)
              
              local displayIdentity = currentUser.name
              if currentUser.name == "Ibrahim Ansari" then displayIdentity = "Official Account of Ibrahim" end
              
              local payload = string.format('{"user":"%s","message":"%s","time":%d,"is_voice":true}', escapeJsonPayload(displayIdentity), escapeJsonPayload(voiceTextPayload), os.time())
              BTP_Core.Http.post(TARGET_ENDPOINT_URL, payload, function(code, body)
                RunUI(function()
                  btnSendVoice.setEnabled(true)
                  if code == 200 or code == 201 then
                    btnSendVoice.setVisibility(BTP_Core.View.GONE)
                    pcall(function() BTP_Core.File(activeRecordingPath).delete() end)
                    activeRecordingPath = ""
                    if syncLiveChatEngine then syncLiveChatEngine() end
                  end
                end)
              end)
            else
              btnSendVoice.setEnabled(true)
              BTP_Core.Toast.makeText(activity, "Error compiling verification token.", BTP_Core.Toast.LENGTH_SHORT).show()
            end
          else
            btnSendVoice.setEnabled(true)
            BTP_Core.Toast.makeText(activity, "Upload failed. Please try again.", BTP_Core.Toast.LENGTH_SHORT).show()
          end
        end)
      end)
    end
  end

  syncLiveChatEngine = function()
    local currentTime = os.time()
    
    if currentActiveRoom ~= "Public Chatroom" and currentRoomCreator ~= currentUser.name then
       local safeMe = cleanFirebaseKey(currentUser.name)
       BTP_Core.Http.get(REQUESTS_URL .. safeRoomNode .. "/" .. safeMe .. ".json", function(kCode, kBody)
         if kCode == 200 and kBody and kBody ~= "null" then
            local userStatus = kBody:match('"status":"([^"]+)"')
            if userStatus == "declined" then
               RunUI(function()
                 inChatroomScope = false
                 if tickers.Fetch then tickers.Fetch.stop() end
                 updateMyPresence(currentActiveRoom, "offline")
                 BTP_Core.Http.delete(REQUESTS_URL .. safeRoomNode .. "/" .. safeMe .. ".json", function(c,b) end)
                 triggerSpeech("Your join request to this private room has been declined.")
                 BTP_Core.Toast.makeText(activity, "You have been declined from this room matrix!", BTP_Core.Toast.LENGTH_LONG).show()
                 showDashboardWindow()
               end)
            end
         end
       end)
    end

    if currentActiveRoom ~= "Public Chatroom" and currentRoomCreator == currentUser.name then
       BTP_Core.Http.get(REQUESTS_URL .. safeRoomNode .. ".json", function(reqCode, reqBody)
         RunUI(function()
           requestBarContainer.removeAllViews()
           if reqCode == 200 and reqBody and reqBody ~= "null" then
              requestBarContainer.setVisibility(BTP_Core.View.VISIBLE)
              for rKey, rData in reqBody:gmatch('"([^"]+)":({[^}]+})') do
                 local requesterName = rData:match('"requester":"([^"]+)"')
                 local status = rData:match('"status":"([^"]+)"')
                 
                 if requesterName and status == "pending" then
                    triggerSpeech("New join request from " .. requesterName)
                    local itemBtn = BTP_Core.Button(activity)
                    itemBtn.setText(string.format("%s requested to stay. Tap to action.", requesterName))
                    itemBtn.setBackgroundColor(BTP_Core.Color.parseColor("#E65100"))
                    itemBtn.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
                    
                    itemBtn.setOnClickListener(BTP_Core.View.OnClickListener{
                      onClick = function(v)
                         local actionDiag = BTP_Core.AlertDialog.Builder(activity)
                         actionDiag.setTitle("Manage Room Access")
                         actionDiag.setMessage("Allow " .. requesterName .. " to remain inside room matrix?")
                         actionDiag.setPositiveButton("Accept", BTP_Core.DialogInterface.OnClickListener{
                           onClick = function(d,w)
                              BTP_Core.Http.put(REQUESTS_URL .. safeRoomNode .. "/" .. rKey .. "/status.json", '"accepted"', function(c,b) 
                                RunUI(function()
                                  triggerSpeech(requesterName .. " joined the room.")
                                  local joinedNotice = string.format('{"user":"System","message":"%s has joined the chatroom.","time":%d,"is_voice":false}', escapeJsonPayload(requesterName), os.time())
                                  BTP_Core.Http.post(TARGET_ENDPOINT_URL, joinedNotice, function(c2,b2) end)
                                end)
                              end)
                           end
                         })
                         actionDiag.setNegativeButton("Decline", BTP_Core.DialogInterface.OnClickListener{
                           onClick = function(d,w)
                              BTP_Core.Http.put(REQUESTS_URL .. safeRoomNode .. "/" .. rKey .. "/status.json", '"declined"', function(c,b) end)
                           end
                         })
                         actionDiag.show()
                      end
                    })
                    requestBarContainer.addView(itemBtn)
                 end
              end
           else
              requestBarContainer.setVisibility(BTP_Core.View.GONE)
           end
         end)
       end)
    end

    BTP_Core.Http.get(ACTIVE_STATUS_URL .. safeRoomNode .. ".json", function(stCode, stBody)
      RunUI(function()
        if stCode == 200 and stBody and stBody ~= "null" then
          local userCount = 0
          local stateStrings = {}
          for uName, uData in stBody:gmatch('"([^"]+)":({[^}]+})') do
            local lastSeen = uData:match('"last_seen":([-%d]+)')
            local stateStr = uData:match('"state":"([^"]+)"') or "active"
            if lastSeen and (currentTime - tonumber(lastSeen)) < 15 then
               userCount = userCount + 1 
               if stateStr ~= "active" then
                 table.insert(stateStrings, uName .. " is " .. stateStr)
               end
            end
          end
          if #stateStrings > 0 then
            statusDisplayLabel.setText(table.concat(stateStrings, " | "))
          else
            statusDisplayLabel.setText("Active Users: " .. tostring(userCount))
          end
        else
          statusDisplayLabel.setText("Active Users: 0")
        end
      end)
    end)

    BTP_Core.Http.get(TARGET_ENDPOINT_URL, function(code, body)
      RunUI(function()
        if code == 200 and body and body ~= "null" then
          local newKeysMapping = {}
          local loopCount = 0
          for key, rawPayload in body:gmatch('"([^"]+)":({[^}]+})') do
            local user = formatUserName(rawPayload:match('"user":"(.-)"'))
            local msg = rawPayload:match('"message":"(.-)"')
            local isVoiceStr = rawPayload:match('"is_voice":([^,}%s]+)')
            local isVoice = (isVoiceStr == "true")
            
            if msg == "ROOM_DELETION_SIGNAL_EVENT" then
              inChatroomScope = false
              if tickers.Fetch then tickers.Fetch.stop() end
              BTP_Core.Toast.makeText(activity, "Room closed by the creator.", BTP_Core.Toast.LENGTH_LONG).show()
              showDashboardWindow()
              return
            end
            
            loopCount = loopCount + 1
            
            local cleanMsg = msg and msg:gsub(">+$", "") or ""
            if cleanMsg ~= "" then
              cleanMsg = cleanMsg:gsub("\\/", "/")
            end
            
            local customDisplayText = string.format("%s: %s", user, cleanMsg)
            
            if isVoice then
              customDisplayText = string.format("%s:\n[Voice Message Note - Tap to Listen]", user)
            end
            
            if not knownBlockedUsers[user] then
              table.insert(newKeysMapping, {key = key, user = user, text = cleanMsg, is_voice = isVoice, display = customDisplayText})
            end
            
            if not announcedMessages[key] then
              announcedMessages[key] = true
              if user ~= currentUser.name and user ~= "System" then
                if isVoice then
                  triggerSpeech("New voice message from " .. user)
                else
                  triggerSpeech("New message from " .. user)
                end
              end
            end
          end

          if loopCount ~= #rawKeysMapping then
            adapter.clear()
            rawKeysMapping = newKeysMapping
            for _, item in ipairs(rawKeysMapping) do adapter.add(item.display) end
          end
        else
          if #rawKeysMapping > 0 then
            adapter.clear()
            rawKeysMapping = {}
          end
        end
      end)
    end)
  end

  btnSend.onClick = function()
    local text = tostring(msgInput.getText()):gsub("^%s*(.-)%s*$", "%1")
    if text ~= "" then
      local safeMe = cleanFirebaseKey(currentUser.name)
      if knownMutedUsers[safeMe] then
        BTP_Core.Toast.makeText(activity, "Error: You are muted in this room.", BTP_Core.Toast.LENGTH_SHORT).show()
        return
      end

      local lowerText = text:lower()
      if (lowerText:find("verified") or lowerText:find("✓") or lowerText:find("system")) and currentUser.name ~= "Ibrahim Ansari" then
         BTP_Core.Toast.makeText(activity, "Error: Text galat hai. Status use nahi kar sakte.", BTP_Core.Toast.LENGTH_SHORT).show()
         return
      end

      playAudioAsset("message_send_default")
      
      local displayIdentity = currentUser.name
      if currentUser.name == "Ibrahim Ansari" then displayIdentity = "Ibrahim Ansari [Verified]" end
      
      local payload = string.format('{"user":"%s","message":"%s","time":%d,"is_voice":false}', escapeJsonPayload(displayIdentity), escapeJsonPayload(text), os.time())
      BTP_Core.Http.post(TARGET_ENDPOINT_URL, payload, function(code, body)
        RunUI(function()
          msgInput.setText("")
          updateMyPresence(currentActiveRoom, "active")
          if currentActiveRoom ~= "Public Chatroom" then
             local updatePayload = string.format('{"name":"%s","creator":"%s","last_active":%d}', escapeJsonPayload(currentActiveRoom), escapeJsonPayload(currentRoomCreator), os.time())
             BTP_Core.Http.put(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", updatePayload, function(c3, b3) end)
          end
          if syncLiveChatEngine then syncLiveChatEngine() end
        end)
      end)
    end
  end

  msgList.onItemClick = function(parent, view, position, id)
    local targetNode = rawKeysMapping[position + 1]
    if targetNode and targetNode.is_voice then
      local audioFilePath = targetNode.text:match("Path: (.-)%]")
      if audioFilePath then
         BTP_Core.Toast.makeText(activity, "Playing voice asset stream...", BTP_Core.Toast.LENGTH_SHORT).show()
         playDirectAudioFile(audioFilePath)
      else
         BTP_Core.Toast.makeText(activity, "Audio file track location error.", BTP_Core.Toast.LENGTH_SHORT).show()
      end
    end
  end

  msgList.onItemLongClick = function(parent, view, position, id)
    local targetNode = rawKeysMapping[position + 1]
    if not targetNode then return true end

    local menuOptions = {"Copy Message", "Reply", "Add Reaction (❤️)", "Add Reaction (👍)"}
    
    if currentRoomCreator == currentUser.name and targetNode.user ~= currentUser.name then
      table.insert(menuOptions, "Mute User")
      table.insert(menuOptions, "Block User")
      table.insert(menuOptions, "Transfer Ownership")
    end
    
    table.insert(menuOptions, "Delete Message")
    table.insert(menuOptions, "Edit Message")

    local builder = BTP_Core.AlertDialog.Builder(activity)
    builder.setTitle("Message Actions")
    builder.setItems(menuOptions, BTP_Core.DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        local selectedAction = menuOptions[which + 1]

        if selectedAction == "Copy Message" then
          local clipboard = activity.getSystemService(BTP_Core.Context.CLIPBOARD_SERVICE)
          clipboard.setText(targetNode.text or "")
          BTP_Core.Toast.makeText(activity, "Copied to clipboard", BTP_Core.Toast.LENGTH_SHORT).show()

        elseif selectedAction == "Reply" then
          msgInput.setText("Replying to @" .. targetNode.user .. ": ")
          msgInput.requestFocus()

        elseif selectedAction == "Mute User" then
          knownMutedUsers[cleanFirebaseKey(targetNode.user)] = true
          BTP_Core.Toast.makeText(activity, "User muted successfully.", BTP_Core.Toast.LENGTH_SHORT).show()

        elseif selectedAction == "Block User" then
          knownBlockedUsers[targetNode.user] = true
          BTP_Core.Toast.makeText(activity, "User blocked from chat visual layer.", BTP_Core.Toast.LENGTH_SHORT).show()
          if syncLiveChatEngine then syncLiveChatEngine() end

        elseif selectedAction == "Transfer Ownership" then
          local transferPayload = string.format('{"name":"%s","creator":"%s","last_active":%d}', escapeJsonPayload(currentActiveRoom), escapeJsonPayload(targetNode.user), os.time())
          BTP_Core.Http.put(CUSTOM_ROOMS_URL .. safeRoomNode .. ".json", transferPayload, function(cT, bT)
            RunUI(function()
              currentRoomCreator = targetNode.user
              BTP_Core.Toast.makeText(activity, "Ownership transferred successfully.", BTP_Core.Toast.SHORT).show()
            end)
          end)

        elseif selectedAction == "Add Reaction (❤️)" or selectedAction == "Add Reaction (👍)" then
          local emoji = selectedAction:match("%((.-)%)")
          local updatedText = (targetNode.text or "") .. " " .. emoji
          local updateUrl = TARGET_ENDPOINT_URL:gsub("%.json$", "/" .. targetNode.key .. ".json")
          local payload = string.format('{"user":"%s","message":"%s","time":%d,"is_voice":%s}', escapeJsonPayload(targetNode.user), escapeJsonPayload(updatedText), os.time(), tostring(targetNode.is_voice))
          BTP_Core.Http.put(updateUrl, payload, function(c, b) RunUI(function() if syncLiveChatEngine then syncLiveChatEngine() end end) end)

        elseif selectedAction == "Edit Message" then
          if targetNode.user == currentUser.name or currentUser.name == "Ibrahim Ansari" then
            local edField = BTP_Core.EditText(activity)
            edField.setText(targetNode.text)
            local edDiag = BTP_Core.AlertDialog.Builder(activity)
            edDiag.setTitle("Edit Message")
            edDiag.setView(edField)
            edDiag.setPositiveButton("Save", BTP_Core.DialogInterface.OnClickListener{
              onClick = function(dEd, wEd)
                local newTxt = tostring(edField.getText())
                local edUrl = TARGET_ENDPOINT_URL:gsub("%.json$", "/" .. targetNode.key .. ".json")
                local payload = string.format('{"user":"%s","message":"%s","time":%d,"is_voice":%s}', escapeJsonPayload(targetNode.user), escapeJsonPayload(newTxt), os.time(), tostring(targetNode.is_voice))
                BTP_Core.Http.put(edUrl, payload, function(c, b) RunUI(function() if syncLiveChatEngine then syncLiveChatEngine() end end) end)
              end
            })
            edDiag.show()
          else
            BTP_Core.Toast.makeText(activity, "Permission Denied!", BTP_Core.Toast.LENGTH_SHORT).show()
          end

        elseif selectedAction == "Delete Message" then
          if targetNode.user == currentUser.name or currentRoomCreator == currentUser.name or currentUser.name == "Ibrahim Ansari" then
             local deleteUrl = TARGET_ENDPOINT_URL:gsub("%.json$", "/" .. targetNode.key .. ".json")
             BTP_Core.Http.delete(deleteUrl, function(c, b)
               RunUI(function()
                 BTP_Core.Toast.makeText(activity, "Message Deleted", BTP_Core.Toast.LENGTH_SHORT).show()
                 if syncLiveChatEngine then syncLiveChatEngine() end
               end)
             end)
          else
             BTP_Core.Toast.makeText(activity, "Permission Denied!", BTP_Core.Toast.LENGTH_SHORT).show()
          end
        end
      end
    })
    builder.show()
    return true
  end

  tickers.Fetch = BTP_Core.Ticker()
  tickers.Fetch.Period = 3500
  tickers.Fetch.onTick = function() 
    if inChatroomScope and syncLiveChatEngine then 
      syncLiveChatEngine() 
      updateMyPresence(currentActiveRoom, "active")
    end 
  end
  tickers.Fetch.start()
  if syncLiveChatEngine then syncLiveChatEngine() end
end

-- ==========================================
-- SYSTEM SETTINGS TERMINAL ARRAY
-- ==========================================
openBTPSettings = function()
  inChatroomScope = false
  local settingsLayout = BTP_Core.LinearLayout(activity)
  settingsLayout.setOrientation(BTP_Core.LinearLayout.VERTICAL)
  settingsLayout.setBackgroundColor(BTP_Core.Color.parseColor(THEME_BG))
  settingsLayout.setPadding(40, 40, 40, 40)

  local titleSettings = BTP_Core.TextView(activity)
  titleSettings.setText("BTP Settings")
  titleSettings.setTextSize(20)
  titleSettings.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  titleSettings.setPadding(0, 0, 0, 20)
  applyAccessibilityNode(titleSettings, "BTP Settings configuration header layout", true)
  settingsLayout.addView(titleSettings)

  local ttsToggleCheckbox = BTP_Core.CheckBox(activity)
  ttsToggleCheckbox.setText("Enable Realtime TTS Voice Output")
  ttsToggleCheckbox.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  ttsToggleCheckbox.setChecked(sp.getBoolean("tts_enabled", true))
  applyAccessibilityNode(ttsToggleCheckbox, "Toggle switch for TTS engine output")
  settingsLayout.addView(ttsToggleCheckbox)
  
  ttsToggleCheckbox.setOnCheckedChangeListener{
    onCheckedChanged = function(buttonView, isChecked)
      sp.edit().putBoolean("tts_enabled", isChecked).commit()
      BTP_Core.Toast.makeText(activity, "TTS Engine state synced in real-time.", BTP_Core.Toast.LENGTH_SHORT).show()
    end
  }

  local btnSelectEngine = BTP_Core.Button(activity)
  btnSelectEngine.setText("System TTS Engine Target: Google TTS")
  btnSelectEngine.setBackgroundColor(BTP_Core.Color.parseColor("#333333"))
  btnSelectEngine.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  applyAccessibilityNode(btnSelectEngine, "Launches default Android system TTS panel settings")
  settingsLayout.addView(btnSelectEngine)
  
  btnSelectEngine.onClick = function()
    local success, err = pcall(function()
      local intent = BTP_Core.Intent("com.android.settings.TTS_SETTINGS")
      intent.setFlags(BTP_Core.Intent.FLAG_ACTIVITY_NEW_TASK)
      activity.startActivity(intent)
      BTP_Core.Toast.makeText(activity, "Select preferred TTS from System Dashboard", BTP_Core.Toast.LENGTH_LONG).show()
    end)
    if not success then
      BTP_Core.Toast.makeText(activity, "Launch Error: " .. tostring(err), 1).show()
    end
  end

  local pitchLabel = BTP_Core.TextView(activity)
  pitchLabel.setText(string.format("TTS Voice Pitch: %.1f%%", sp.getFloat("tts_pitch", 1.0) * 50))
  pitchLabel.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  pitchLabel.setPadding(0, 20, 0, 5)
  settingsLayout.addView(pitchLabel)

  local pitchSeekBar = BTP_Core.SeekBar(activity)
  pitchSeekBar.setMax(20)
  pitchSeekBar.setProgress(math.floor(sp.getFloat("tts_pitch", 1.0) * 10))
  settingsLayout.addView(pitchSeekBar)

  local speedLabel = BTP_Core.TextView(activity)
  speedLabel.setText(string.format("TTS Speech Speed: %.1f%%", sp.getFloat("tts_speed", 1.0) * 50))
  speedLabel.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  speedLabel.setPadding(0, 20, 0, 5)
  settingsLayout.addView(speedLabel)

  local speedSeekBar = BTP_Core.SeekBar(activity)
  speedSeekBar.setMax(20)
  speedSeekBar.setProgress(math.floor(sp.getFloat("tts_speed", 1.0) * 10))
  settingsLayout.addView(speedSeekBar)

  local function updateSeekBarLabels()
    pitchLabel.setText(string.format("TTS Voice Pitch: %.1f%%", (pitchSeekBar.getProgress() / 10) * 50))
    speedLabel.setText(string.format("TTS Speech Speed: %.1f%%", (speedSeekBar.getProgress() / 10) * 50))
    
    local tempPitch = pitchSeekBar.getProgress() / 10
    local tempSpeed = speedSeekBar.getProgress() / 10
    if tempPitch < 0.1 then tempPitch = 0.1 end
    if tempSpeed < 0.1 then tempSpeed = 0.1 end
    
    sp.edit().putFloat("tts_pitch", tempPitch).putFloat("tts_speed", tempSpeed).commit()
    
    if ttsEngine then
       ttsEngine.setPitch(tempPitch)
       ttsEngine.setSpeechRate(tempSpeed)
    end
  end

  pitchSeekBar.setOnSeekBarChangeListener{
    onProgressChanged = function(s, p, fromUser) if fromUser then updateSeekBarLabels() end end
  }
  speedSeekBar.setOnSeekBarChangeListener{
    onProgressChanged = function(s, p, fromUser) if fromUser then updateSeekBarLabels() end end
  }

  local btnTestTts = BTP_Core.Button(activity)
  btnTestTts.setText("Test Speech Playback")
  btnTestTts.setBackgroundColor(BTP_Core.Color.parseColor(THEME_ACCENT))
  btnTestTts.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  local testLP = BTP_Core.LinearLayout.LayoutParams(BTP_Core.LinearLayout.LayoutParams.MATCH_PARENT, BTP_Core.LinearLayout.LayoutParams.WRAP_CONTENT)
  testLP.setMargins(0, 25, 0, 0)
  btnTestTts.setLayoutParams(testLP)
  settingsLayout.addView(btnTestTts)

  btnTestTts.onClick = function()
    if ttsEngine then
      local tempPitch = pitchSeekBar.getProgress() / 10
      local tempSpeed = speedSeekBar.getProgress() / 10
      if tempPitch < 0.1 then tempPitch = 0.1 end
      if tempSpeed < 0.1 then tempSpeed = 0.1 end
      ttsEngine.setPitch(tempPitch)
      ttsEngine.setSpeechRate(tempSpeed)
      ttsEngine.speak("This is a speech synthesis test validation for BTP Chat Friend application.", BTP_Core.TextToSpeech.QUEUE_FLUSH, nil)
    end
  end

  local btnApplySettings = BTP_Core.Button(activity)
  btnApplySettings.setText("Apply and Save Parameters")
  btnApplySettings.setBackgroundColor(BTP_Core.Color.parseColor(THEME_SUCCESS))
  btnApplySettings.setTextColor(BTP_Core.Color.parseColor("#000000"))
  btnApplySettings.setLayoutParams(testLP)
  settingsLayout.addView(btnApplySettings)

  btnApplySettings.onClick = function()
    local targetPitch = pitchSeekBar.getProgress() / 10
    local targetSpeed = speedSeekBar.getProgress() / 10
    if targetPitch < 0.1 then targetPitch = 0.1 end
    if targetSpeed < 0.1 then targetSpeed = 0.1 end
    
    sp.edit()
      .putFloat("tts_pitch", targetPitch)
      .putFloat("tts_speed", targetSpeed)
      .commit()
      
    BTP_Core.Toast.makeText(activity, "TTS configuration matrix updated permanently.", BTP_Core.Toast.LENGTH_SHORT).show()
  end

  local btnManualUpdate = BTP_Core.Button(activity)
  btnManualUpdate.setText("Check Application Updates")
  btnManualUpdate.setBackgroundColor(BTP_Core.Color.parseColor("#FF9800"))
  btnManualUpdate.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnManualUpdate.setLayoutParams(testLP)
  settingsLayout.addView(btnManualUpdate)
  
  btnManualUpdate.onClick = function() checkApplicationUpdates(false) end

  local btnFeedback = BTP_Core.Button(activity)
  btnFeedback.setText("Send Back to Developer")
  btnFeedback.setBackgroundColor(BTP_Core.Color.parseColor("#0288D1"))
  btnFeedback.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnFeedback.setLayoutParams(testLP)
  settingsLayout.addView(btnFeedback)

  btnFeedback.onClick = function()
     local feedbackContainer = BTP_Core.LinearLayout(activity)
     feedbackContainer.setOrientation(BTP_Core.LinearLayout.VERTICAL)
     feedbackContainer.setPadding(30, 20, 30, 20)
     
     local labelDevName = BTP_Core.TextView(activity)
     labelDevName.setText("Developer Name: Ibrahim Ansari")
     labelDevName.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
     feedbackContainer.addView(labelDevName)
     
     local inputUser = BTP_Core.EditText(activity)
     inputUser.setText(currentUser.name)
     inputUser.setEnabled(false)
     inputUser.setTextColor(BTP_Core.Color.parseColor("#888888"))
     feedbackContainer.addView(inputUser)
     
     local inputWhatsApp = BTP_Core.EditText(activity)
     inputWhatsApp.setHint("Your WhatsApp Number (e.g. 91xxxxxxxxxx)")
     inputWhatsApp.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
     feedbackContainer.addView(inputWhatsApp)
     
     local inputBugReport = BTP_Core.EditText(activity)
     inputBugReport.setHint("Write down your bug report and feedback details here...")
     inputBugReport.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
     feedbackContainer.addView(inputBugReport)
     
     local feedbackDiag = BTP_Core.AlertDialog.Builder(activity)
     feedbackDiag.setTitle("Report System Bug")
     feedbackDiag.setView(feedbackContainer)
     feedbackDiag.setPositiveButton("Send via WhatsApp", BTP_Core.DialogInterface.OnClickListener{
       onClick = function(d, w)
          local reportMsg = tostring(inputBugReport.getText())
          local userContact = tostring(inputWhatsApp.getText())
          if reportMsg ~= "" and userContact ~= "" then
             local success, err = pcall(function()
                local rawUrl = "https://api.whatsapp.com/send?phone=917481878723&text=" .. 
                               BTP_Core.Uri.encode(string.format("[App: BTP Chat Friend]\n[Sender: %s]\n[Contact: %s]\n\n[Report Matrix]:\n%s", currentUser.name, userContact, reportMsg))
                local intent = BTP_Core.Intent(BTP_Core.Intent.ACTION_VIEW, BTP_Core.Uri.parse(rawUrl))
                intent.setFlags(BTP_Core.Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
             end)
             if not success then
                BTP_Core.Toast.makeText(activity, "Error opening WhatsApp: " .. tostring(err), 1).show()
             end
          else
             BTP_Core.Toast.makeText(activity, "All input data parameters are required!", BTP_Core.Toast.LENGTH_SHORT).show()
          end
       end
     })
     feedbackDiag.setNegativeButton("Cancel", nil)
     feedbackDiag.show()
  end

  local btnAbout = BTP_Core.Button(activity)
  btnAbout.setText("About BTP Chat")
  btnAbout.setBackgroundColor(BTP_Core.Color.parseColor("#424242"))
  btnAbout.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnAbout.setLayoutParams(testLP)
  settingsLayout.addView(btnAbout)

  btnAbout.onClick = function()
    local aboutDialog = BTP_Core.AlertDialog.Builder(activity)
    aboutDialog.setTitle("About BTP Chat Matrix")
    aboutDialog.setMessage("BTP Chat Friend\nApplication Version: v" .. CURRENT_VERSION .. "\n\nDeveloped Exclusively by: Ibrahim Ansari\n\n© 2026 Ibrahim Ansari. All Rights Reserved. Architecture built for low-latency network pipelines and secure message routing data streams.")
    aboutDialog.setPositiveButton("OK", nil)
    aboutDialog.show()
  end

  local btnLogout = BTP_Core.Button(activity)
  btnLogout.setText("Logout Profile Matrix")
  btnLogout.setBackgroundColor(BTP_Core.Color.parseColor(THEME_DANGER))
  btnLogout.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnLogout.setLayoutParams(testLP)
  settingsLayout.addView(btnLogout)

  local btnBack = BTP_Core.Button(activity)
  btnBack.setText("Back To Console Map")
  btnBack.setBackgroundColor(BTP_Core.Color.parseColor("#424242"))
  btnBack.setTextColor(BTP_Core.Color.parseColor("#FFFFFF"))
  btnBack.setLayoutParams(testLP)
  settingsLayout.addView(btnBack)

  activity.ContentView = settingsLayout

  btnLogout.onClick = function()
    local safeNameNode = cleanFirebaseKey(currentUser.name)
    local clearSessionUrl = USERS_URL .. safeNameNode .. "/session.json"
    BTP_Core.Http.put(clearSessionUrl, '"inactive"', function(c, b)
      RunUI(function()
        sp.edit().putString("username", "").putString("secure_code", "").commit()
        activity.finish()
      end)
    end)
  end

  btnBack.onClick = function() showDashboardWindow() end
end

-- ==========================================
-- EXECUTION ENGINE STARTUP INITIALIZATION
-- ==========================================
if savedName ~= "" and savedCode ~= "" then
  currentUser.name = formatUserName(savedName)
  currentUser.secureCode = savedCode
  showDashboardWindow()
else
  showLoginWindow()
end
