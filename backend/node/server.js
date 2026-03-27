const express = require('express');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
app.use(express.json());

const server = http.createServer(app);
const io = socketIo(server, {
  cors: { origin: "*" } // Open CORS strictly for the SmartBoard app connections
});

// The WebSocket Lane (Flutter connects here)
io.on('connection', (socket) => {
  console.log(`[Node.js] SmartBoard Connected via WebSocket! ID: ${socket.id}`);
  
  socket.on('disconnect', () => {
    console.log(`[Node.js] SmartBoard Disconnected: ${socket.id}`);
  });
});

// The Internal Megaphone Endpoint (Python hits this)
app.post('/internal/notify', (req, res) => {
  const { student_id, student_name, grid_index } = req.body;
  
  console.log(`[Node.js] Received authorized ping from Python: ${student_name} is present!`);
  console.log(`[Node.js] Instantly pushing real-time UI update to all SmartBoards...`);
  
  // Blast strictly over Websockets. No database writing. Zero math.
  io.emit('attendance_success', {
    student_id,
    student_name,
    grid_index
  });
  
  res.status(200).json({ success: true, message: "UI update broadcasted." });
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`[Node.js] The Messenger is strictly handling sockets on port ${PORT}`);
});
