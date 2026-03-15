
## First: You’re thinking correctly ✅

Yes — **physical → digital mapping must be done by a human** at least once:

* Room → GPS coordinates
* Room → Wi-Fi BSSID
* Room → BLE beacon ID
* Room → SmartBoard device
* Room → Seating grid
* Room → Trust radius

This **cannot be automated fully**. Someone must stand inside the room and register it.

---

## The Core Question

> Who should enter Wi-Fi, Bluetooth, GPS, room configs into the database?

Let’s evaluate each role honestly 👇

---

## ❌ Super Admin — WRONG choice for this

**Why Super Admin should NOT do it:**

* Super Admin manages **platform**, not **buildings**
* One Super Admin cannot physically visit 100+ colleges
* It doesn’t scale
* It breaks the SaaS model
* In MNCs, platform owners never touch client infrastructure

**Super Admin should define HOW, not DO.**

---

## ❌ Normal College Admin — ALSO WRONG

College Admin:

* Non-technical
* Office-based
* No understanding of BLE, BSSID, GPS accuracy
* High chance of wrong data → system failure

Giving them raw config access = **danger**

---

## ✅ The CORRECT ROLE (Industry Standard)

### 🔑 You need a **Campus / Room Provisioning Role**

Call it one of these:

* **Infrastructure Admin**
* **Campus IT Admin**
* **Onboarding Admin**
* **Provisioning Officer** (best term)

This role exists in **every enterprise system** (Wi-Fi, ERP, CCTV, biometrics).

---

## Final Role Split (Very Important)

### 1️⃣ SUPER ADMIN (Platform Owner)

**Defines rules, templates, and limits**

Can:

* Define **what data is required** for a room
* Define validation rules
* Lock schema
* Approve provisioning tools
* View provisioning logs
* Disable compromised rooms

❌ Cannot:

* Enter room GPS
* Scan Wi-Fi
* Register BLE beacons

---

### 2️⃣ CAMPUS / INFRASTRUCTURE ADMIN (Physical → Digital)

💡 **This is the key missing role**

**Who is this?**

* College IT staff
* Lab assistant
* System integrator
* Deployment engineer

### What they do (VERY DETAILED):

#### 🏫 Room Provisioning (On-site)

They stand **inside the classroom** and use a **special provisioning app**:

* Scan Wi-Fi → auto-capture BSSID
* Scan BLE beacon → register UUID
* Capture GPS → average over 30–60 seconds
* Register SmartBoard device ID
* Define room type (Lab / Lecture / Seminar)
* Define seating layout
* Assign department & subjects

➡️ All this is **guided**, not manual typing.

---

#### 🔐 Controlled Permissions

They:

* Can ONLY create/update rooms
* Cannot edit attendance records
* Cannot change security rules
* Cannot access other colleges
* Cannot touch backend configs

---

### 3️⃣ COLLEGE ADMIN

**Purely operational**

* Assign faculty to rooms
* Schedule classes
* View attendance
* Handle reports

No hardware, no sensors, no infra.

---

## How Data Enters the Database (IMPORTANT FLOW)

### Step-by-step (Real World)

1️⃣ Super Admin defines **Room Schema**

```text
Room must have:
- GPS radius
- 1 Wi-Fi BSSID
- 1 BLE beacon
- SmartBoard ID
```

2️⃣ Infrastructure Admin opens **Provisioning App**

* App is locked to provisioning mode
* Requires elevated auth

3️⃣ App auto-captures:

* Wi-Fi fingerprints
* BLE UUID
* GPS cluster
* Device signature

4️⃣ Data sent to backend

* Validated against Super Admin rules
* Stored as immutable room config

5️⃣ Room is marked:
✅ “Provisioned & Trusted”

---

## Why This Design Is PERFECT

✔ Scales to thousands of rooms
✔ No technical burden on college admin
✔ No physical dependency on Super Admin
✔ Prevents bad data
✔ Matches MNC architecture
✔ Resume-worthy design

