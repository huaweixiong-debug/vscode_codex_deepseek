const fs = require("fs");

const path = "/root/.codex/config.toml";
let source = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
const stamp = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);

if (fs.existsSync(path)) {
  fs.copyFileSync(path, `${path}.before-docker-deepseek.${stamp}`);
}

source = source.replace(/^model_provider\s*=.*\r?\n/gm, "");
source = source.replace(/^model\s*=.*\r?\n/gm, "");
source = source.replace(/^model_reasoning_effort\s*=.*\r?\n/gm, "");
source = source.replace(/^\[model_providers\.deepseek-codex\][\s\S]*?(?=^\[|\s*$)/m, "");
source = source.trimStart();

const block = `model_provider = "deepseek-codex"
model = "deepseek-v4-pro"
model_reasoning_effort = "high"

[model_providers.deepseek-codex]
name = "DeepSeek Codex"
base_url = "http://127.0.0.1:17777/v1"
wire_api = "responses"

`;

fs.writeFileSync(path, block + source, "utf8");
