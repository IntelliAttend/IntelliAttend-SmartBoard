from fastapi import FastAPI
import uvicorn
import os

app = FastAPI()

@app.get("/")
def read_root():
    return {"status": "ok", "path": os.getcwd()}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
