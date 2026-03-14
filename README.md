# 🖥️ Attendance Smartboard Web

> **Real-time classroom dashboard** that displays live attendance updates on classroom smartboards. Built with React and Firebase Realtime Database.

[![React](https://img.shields.io/badge/React-18.x-61DAFB?logo=react)](https://reactjs.org/)
[![Firebase](https://img.shields.io/badge/Firebase-Realtime%20DB-FFCA28?logo=firebase)](https://firebase.google.com/)
[![Vercel](https://img.shields.io/badge/Deployed%20on-Vercel-000000?logo=vercel)](https://vercel.com/)

---

## 🎯 What This Does

This web application runs on classroom smartboards or projectors, providing teachers and students with **instant visual feedback** on attendance status.

**Key Features:**
- 📊 **Live Updates** - See students checking in as it happens (no page refresh!)
- 🎨 **Clean Interface** - Minimalist design optimized for large displays
- 📈 **Attendance Meter** - Visual percentage bar shows class attendance
- 🔄 **Auto-Sync** - Connects directly to Firebase for real-time data
- 🕒 **Class Period Tracking** - Displays current period and remaining time

---

## 🏗️ Tech Stack

- **React 18** - Component-based UI
- **Firebase Realtime Database** - Live data synchronization
- **React Router** - Navigation between class views
- **TailwindCSS** - Utility-first styling
- **Framer Motion** - Smooth animations
- **Vercel** - Deployment and hosting

---

## 📁 Project Structure

```
attendance-smartboard-web/
├── src/
│   ├── components/
│   │   ├── AttendanceCard.jsx     # Individual student card
│   │   ├── ClassHeader.jsx        # Class info display
│   │   ├── AttendanceMeter.jsx    # Percentage visualization
│   │   └── LiveIndicator.jsx      # "Live" status badge
│   ├── pages/
│   │   ├── Dashboard.jsx          # Main smartboard view
│   │   └── ClassSelector.jsx      # Choose which class to display
│   ├── hooks/
│   │   └── useRealtimeAttendance.js  # Firebase listener hook
│   ├── services/
│   │   └── firebase.js            # Firebase config
│   ├── App.jsx
│   └── index.js
├── public/
├── package.json
└── README.md
```

---

## 🚀 Quick Start

### **1. Clone the Repository**
```bash
git clone git@github.com:YOUR-ORG/attendance-smartboard-web.git
cd attendance-smartboard-web
```

### **2. Install Dependencies**
```bash
npm install
```

### **3. Configure Firebase**
Create a `.env.local` file:
```env
REACT_APP_FIREBASE_API_KEY=your-api-key
REACT_APP_FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
REACT_APP_FIREBASE_DATABASE_URL=https://your-project.firebaseio.com
REACT_APP_FIREBASE_PROJECT_ID=your-project-id
REACT_APP_FIREBASE_STORAGE_BUCKET=your-project.appspot.com
REACT_APP_FIREBASE_MESSAGING_SENDER_ID=123456789
REACT_APP_FIREBASE_APP_ID=1:123456789:web:abcdef
```

### **4. Run the Development Server**
```bash
npm start
```

Visit `http://localhost:3000`

---

## 🖼️ How It Looks

```
┌─────────────────────────────────────────────────────────┐
│  🔴 LIVE                     Class 10A - Math           │
│                          Period 3 | 25 min remaining     │
├─────────────────────────────────────────────────────────┤
│  Attendance: 28/30 (93%)                                │
│  ████████████████████████████░░  93%                    │
├─────────────────────────────────────────────────────────┤
│  ✅ John Smith        ✅ Emily Davis      ✅ Mike Chen  │
│  ✅ Sarah Johnson     ❌ Alex Brown       ✅ Lisa Wang  │
│  ✅ David Lee         ✅ Emma Wilson      ✅ Tom Garcia │
│  ...                                                    │
└─────────────────────────────────────────────────────────┘
```

---

## 🔥 Real-time Connection

The app listens to Firebase changes using this pattern:

```javascript
// In useRealtimeAttendance.js
useEffect(() => {
  const attendanceRef = ref(database, `attendance/class-${classId}`);
  
  onValue(attendanceRef, (snapshot) => {
    const data = snapshot.val();
    setAttendanceData(data);
  });
  
  return () => off(attendanceRef);
}, [classId]);
```

**Every time a student scans their QR code**, Firebase updates, and the smartboard reflects it **instantly** - no manual refresh needed!

---

## 🎨 Customization

### **Change Color Theme**
Edit `tailwind.config.js`:
```javascript
theme: {
  extend: {
    colors: {
      primary: '#3B82F6',    // Blue
      success: '#10B981',    // Green
      warning: '#F59E0B',    // Orange
    }
  }
}
```

### **Adjust Animation Speed**
In `AttendanceCard.jsx`:
```javascript
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.3 }}  // Change this
>
```

---

## 🚀 Deployment

### **Deploy to Vercel (Recommended)**
```bash
npm install -g vercel
vercel login
vercel
```

Follow the prompts. Vercel will auto-detect it's a React app.

**Add Environment Variables in Vercel:**
- Go to your project settings
- Add all `REACT_APP_*` variables
- Redeploy

### **Deploy to Netlify**
```bash
npm run build
netlify deploy --prod --dir=build
```

---

## 🔒 Security Notes

- ✅ Firebase rules are set to **read-only** for this app
- ✅ No sensitive data is stored in the frontend
- ✅ All write operations happen through the backend API

---

## 🤝 Contributing

See the [Organization Contributing Guidelines](https://github.com/YOUR-ORG/.github/blob/main/CONTRIBUTING.md)

---

**🔗 Related Repositories:**
- [Backend API](https://github.com/YOUR-ORG/attendance-server-api)
- [Mobile App](https://github.com/YOUR-ORG/attendance-mobile-app)
- [Admin Panel](https://github.com/YOUR-ORG/attendance-admin-panel)