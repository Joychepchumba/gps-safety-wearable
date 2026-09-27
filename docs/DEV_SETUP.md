# Dev Setup — SafeGuard

## One-time setup

### 1. Install ngrok
```powershell
winget install ngrok.ngrok
```
Then sign up free at https://ngrok.com and run:
```powershell
ngrok config add-authtoken YOUR_NGROK_TOKEN
```
(Your token is on the ngrok dashboard after signup. Free tier is enough.)

### 2. Install Python deps
```powershell
cd backend
pip install -r requirements.txt
```

### 3. Set your backend .env
Copy the example and fill in your Supabase service role key:
```powershell
copy backend\.env.example backend\.env
```
Edit `backend\.env` with your values.

---

## Every dev session (2 steps only)

### Step 1 — Run the launcher (in any terminal)
```powershell
.\scripts\start_dev.ps1
```
OR in VS Code: **Ctrl+Shift+P** → **Run Task** → **Start Dev (backend + ngrok)**

This will:
- Start FastAPI on port 8000
- Open an ngrok HTTPS tunnel
- Auto-update `.vscode/launch.json` with the live backend URL

### Step 2 — Run the Flutter app
Press **F5** in VS Code with your phone connected (USB or wireless).

Select **SafeGuard (dev)** from the device picker.

That's it. The app on your phone talks to the tunnel → your laptop → Supabase.

---

## Testing on iPhone
1. Open Xcode → trust your device
2. Connect iPhone via USB
3. In VS Code device picker, select your iPhone
4. Press F5

## Testing on Android
1. Enable Developer Options → USB Debugging on your phone  
2. Connect via USB
3. In VS Code device picker, select your Android
4. Press F5

## ngrok free tier note
The tunnel URL changes each time you restart ngrok. The script handles this automatically — just re-run `start_dev.ps1` each session. If you want a **fixed permanent URL** (no changes ever), upgrade ngrok to the paid plan or deploy the backend to Railway (free).
