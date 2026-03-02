import gradio as gr
import json
import urllib.request
import urllib.parse
import os
import websocket
import uuid

COMFY_URL = "127.0.0.1:8188"
WORKFLOW_DIR = "/opt/comfyui/user/default/workflows"

def get_workflows():
    try:
        if os.path.exists(WORKFLOW_DIR):
            return [f for f in os.listdir(WORKFLOW_DIR) if f.endswith(".json")]
    except:
        pass
    return ["txt2vid_wan22.json"]

def queue_prompt(prompt_workflow):
    p = {"prompt": prompt_workflow, "client_id": str(uuid.uuid4())}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"http://{COMFY_URL}/prompt", data=data)
    response = urllib.request.urlopen(req)
    return json.loads(response.read())

def get_video_or_image(filename, subfolder, folder_type):
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    url = f"http://{COMFY_URL}/view?{url_values}"
    req = urllib.request.Request(url)
    try:
        response = urllib.request.urlopen(req)
        output_path = f"/tmp/{uuid.uuid4()}_{filename}"
        with open(output_path, 'wb') as f:
            f.write(response.read())
        return output_path
    except:
        return None

def submit_workflow(workflow_file, prompt_text, lora_name=None):
    workflow_path = os.path.join(WORKFLOW_DIR, workflow_file)
    if not os.path.exists(workflow_path):
        workflow_path = workflow_file
        
    try:
        with open(workflow_path, 'r', encoding='utf-8') as f:
            workflow = json.load(f)
    except Exception as e:
        return None, None, f"Error loading workflow: {e}"

    # Auto-find Wan/Clip Text Encoder and update prompt
    for node_id, node in workflow.items():
        if "type" in node:
            if node["type"] in ["WanT5TextEncode", "CLIPTextEncode"] and "text" in node.get("inputs", {}):
                node["inputs"]["text"] = prompt_text
            elif node["type"] in ["WanT5TextEncode", "CLIPTextEncode"] and isinstance(node.get("widgets_values"), list) and len(node["widgets_values"]) > 0:
                node["widgets_values"][0] = prompt_text

    try:
        ws = websocket.WebSocket()
        client_id = str(uuid.uuid4())
        ws.connect(f"ws://{COMFY_URL}/ws?clientId={client_id}")
        
        prompt_data = {"prompt": workflow, "client_id": client_id}
        req = urllib.request.Request(f"http://{COMFY_URL}/prompt", data=json.dumps(prompt_data).encode('utf-8'))
        response = urllib.request.urlopen(req)
        prompt_res = json.loads(response.read())
        prompt_id = prompt_res["prompt_id"]

        output_media = None
        is_video = False

        while True:
            out = ws.recv()
            if isinstance(out, str):
                msg = json.loads(out)
                if msg["type"] == "executed" and msg["data"]["prompt_id"] == prompt_id:
                    # Parse output
                    node_id = msg["data"]["node"]
                    if "images" in msg["data"]["output"]:
                        img = msg["data"]["output"]["images"][0]
                        output_media = get_video_or_image(img["filename"], img["subfolder"], img["type"])
                        break
                    elif "videos" in msg["data"]["output"] or "gifs" in msg["data"]["output"]:
                        v_key = "videos" if "videos" in msg["data"]["output"] else "gifs"
                        vid = msg["data"]["output"][v_key][0]
                        output_media = get_video_or_image(vid["filename"], vid["subfolder"], vid["type"])
                        is_video = True
                        break
        ws.close()
        return output_media, is_video, "Success"
    except Exception as e:
        return None, None, f"Execution Error: {str(e)}"

# Gradio Interface
with gr.Blocks(title="NERV Absolute Backup UI (Wan 2.2 / SD UI)") as demo:
    gr.Markdown("# 🛡️ NERV Backup Gradio Instance\nIf the main Java/Node.js UI fails, this bare-bones instance communicates directly with ComfyUI to ensure 1000% functional access.")
    
    with gr.Row():
        with gr.Column(scale=1):
            workflow_dropdown = gr.Dropdown(label="Select Workflow JSON", choices=get_workflows(), value="txt2vid_wan22.json" if "txt2vid_wan22.json" in get_workflows() else get_workflows()[0] if get_workflows() else None)
            prompt_input = gr.Textbox(label="Prompt", lines=5, placeholder="Enter your prompt here...")
            generate_btn = gr.Button("Generate", variant="primary")
            
        with gr.Column(scale=1):
            output_video = gr.Video(label="Output Video", visible=False)
            output_image = gr.Image(label="Output Image", visible=False)
            status_text = gr.Markdown()
            
    def process(wf, prompt):
        out_path, is_video, msg = submit_workflow(wf, prompt)
        if out_path:
            if is_video or out_path.endswith('.mp4'):
                return [gr.update(value=out_path, visible=True), gr.update(visible=False), f"✅ Generated!"]
            else:
                return [gr.update(visible=False), gr.update(value=out_path, visible=True), f"✅ Generated!"]
        return [gr.update(visible=False), gr.update(visible=False), f"❌ {msg}"]

    generate_btn.click(fn=process, inputs=[workflow_dropdown, prompt_input], outputs=[output_video, output_image, status_text])

if __name__ == "__main__":
    # Wait for comfy socket to be up
    demo.launch(server_name="0.0.0.0", server_port=7860)
