use axum::{
    Router,
    extract::State,
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    http::StatusCode,
    response::{Html, IntoResponse, Json},
    routing::{get, post},
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::io::{Read as _, Write as _};
use std::mem;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::signal;
use tokio::sync::Mutex;
use tower_http::services::ServeDir;

struct AppState {
    display: u32,
}

struct Processes {
    vnc: Child,
    websockify: Child,
}

#[derive(Deserialize)]
struct FontSizeRequest {
    size: f32,
}

#[derive(Serialize)]
struct FontSizeResponse {
    success: bool,
    message: String,
}

fn find_available_display() -> u32 {
    for display in 1..100 {
        let lock_file = format!("/tmp/.X{}-lock", display);
        if !Path::new(&lock_file).exists() {
            return display;
        }
    }
    panic!("No available display found");
}

fn start_vnc_server(display: u32, geometry: &str) -> Child {
    let vnc = Command::new("Xvnc")
        .args([
            &format!(":{}", display),
            "-geometry",
            geometry,
            "-depth",
            "24",
            "-SecurityTypes",
            "None",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();

    match vnc {
        Ok(child) => child,
        Err(_) => {
            eprintln!("Xvnc not found, trying vncserver...");
            Command::new("vncserver")
                .args([
                    &format!(":{}", display),
                    "-geometry",
                    geometry,
                    "-depth",
                    "24",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .expect("Failed to start VNC server. Install tigervnc.")
        }
    }
}

fn start_websockify(vnc_port: u32, ws_port: u32) -> Child {
    Command::new("websockify")
        .args([
            "--web=/usr/share/novnc",
            &format!("0.0.0.0:{}", ws_port),
            &format!("localhost:{}", vnc_port),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("Failed to start websockify. Install novnc.")
}

fn start_window_manager(display: u32) -> Child {
    let display_env = format!(":{}", display);
    Command::new("ratpoison")
        .env("DISPLAY", &display_env)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("Failed to start ratpoison window manager")
}

fn find_terminal() -> &'static str {
    "alacritty"
}

fn start_terminal_with_agent(
    display: u32,
    repo_path: &str,
    terminal: &str,
    geometry: &str,
) -> Child {
    let display_env = format!(":{}", display);
    // Use agent-wrapper.sh to handle any configured agent CLI
    let agent_cmd = format!("cd -- {} && /usr/local/bin/agent", repo_path);

    let mut cmd = Command::new(terminal);
    cmd.env("DISPLAY", &display_env);

    // Pass through important env vars
    if let Ok(claude_dir) = env::var("CLAUDE_CONFIG_DIR") {
        println!("Passing CLAUDE_CONFIG_DIR={} to terminal", claude_dir);
        cmd.env("CLAUDE_CONFIG_DIR", &claude_dir);
    }
    if let Ok(home) = env::var("HOME") {
        cmd.env("HOME", &home);
    }

    match terminal {
        "wezterm" => {
            cmd.args([
                "start",
                "--always-new-process",
                "--",
                "bash",
                "-c",
                &agent_cmd,
            ]);
        }
        "alacritty" => {
            cmd.args(["-e", "bash", "-c", &agent_cmd]);
        }
        "kitty" => {
            cmd.args(["--start-as", "fullscreen", "bash", "-c", &agent_cmd]);
        }
        "xterm" => {
            cmd.args([
                "-maximized",
                "-fa",
                "Monospace",
                "-fs",
                "14",
                "-bg",
                "black",
                "-fg",
                "white",
                "-e",
                "bash",
                "-c",
                &agent_cmd,
            ]);
        }
        "urxvt" => {
            cmd.args(["-geometry", geometry, "-e", "bash", "-c", &agent_cmd]);
        }
        "st" => {
            cmd.args(["-e", "bash", "-c", &agent_cmd]);
        }
        _ => {
            cmd.args(["-e", "bash", "-c", &agent_cmd]);
        }
    }

    cmd.spawn().expect("Failed to start terminal")
}

async fn send_text_to_display(display: u32, text: &str) {
    let display_env = format!(":{}", display);

    println!("Sending text to display :{} - '{}'", display, text);

    // Retry finding the window a few times in case terminal is restarting
    let mut focus_ok = false;
    for attempt in 0..10 {
        let output = Command::new("xdotool")
            .env("DISPLAY", &display_env)
            .args(["search", "--class", "Alacritty"])
            .output();

        if let Ok(out) = &output
            && !out.stdout.is_empty()
        {
            // Window found, now focus it
            let focus_result = Command::new("xdotool")
                .env("DISPLAY", &display_env)
                .args(["search", "--class", "Alacritty", "windowfocus", "--sync"])
                .status();
            println!(
                "xdotool focus result (attempt {}): {:?}",
                attempt, focus_result
            );
            focus_ok = focus_result.map(|s| s.success()).unwrap_or(false);
            if focus_ok {
                break;
            }
        }

        println!("Window not found, retrying... (attempt {})", attempt);
        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    if !focus_ok {
        println!("Failed to focus terminal window after retries");
        return;
    }

    // Type the text and press Enter
    let type_result = Command::new("xdotool")
        .env("DISPLAY", &display_env)
        .args(["type", "--clearmodifiers", text])
        .status();
    println!("xdotool type result: {:?}", type_result);

    let key_result = Command::new("xdotool")
        .env("DISPLAY", &display_env)
        .args(["key", "Return"])
        .status();
    println!("xdotool key result: {:?}", key_result);
}

async fn index_handler() -> Html<&'static str> {
    Html(include_str!("index.html"))
}

async fn prompt_ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_prompt_socket(socket, state))
}

async fn handle_prompt_socket(mut socket: WebSocket, state: Arc<AppState>) {
    let display = state.display;
    println!("Prompt WebSocket connected");
    while let Some(msg) = socket.next().await {
        println!("WebSocket received: {:?}", msg);
        if let Ok(Message::Text(text)) = msg {
            // Use xdotool to type into the X display
            send_text_to_display(display, &text).await;
        }
    }
    println!("Prompt WebSocket disconnected");
}

async fn font_size_handler(
    State(_state): State<Arc<AppState>>,
    Json(request): Json<FontSizeRequest>,
) -> Result<Json<FontSizeResponse>, (StatusCode, Json<FontSizeResponse>)> {
    println!("Font size change request: {}", request.size);

    // Validate the font size
    let size = match validate_font_size(request.size) {
        Ok(s) => s,
        Err(e) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(FontSizeResponse {
                    success: false,
                    message: e,
                }),
            ));
        }
    };

    // Update the config file
    // Alacritty will automatically reload the config when the file changes (live_config_reload)
    if let Err(e) = update_alacritty_config(size) {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(FontSizeResponse {
                success: false,
                message: e,
            }),
        ));
    }

    Ok(Json(FontSizeResponse {
        success: true,
        message: format!("Font size updated to {}", size),
    }))
}

fn validate_args(args: &[String]) -> Result<(String, String, u16), String> {
    if args.len() < 2 {
        return Err("Usage: vnccc <repo-path> [geometry] [web-port]".to_string());
    }

    let repo_path = args[1].clone();
    let geometry = args
        .get(2)
        .map(|s| s.as_str())
        .unwrap_or("1024x1024")
        .to_string();
    let web_port: u16 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(8080);

    if !Path::new(&repo_path).exists() {
        return Err(format!("Error: repo path '{}' does not exist", repo_path));
    }

    Ok((repo_path, geometry, web_port))
}

fn validate_font_size(size: f32) -> Result<f32, String> {
    if !size.is_finite() {
        return Err("Font size must be a valid number".to_string());
    }
    if !(8.0..=72.0).contains(&size) {
        return Err(format!(
            "Font size must be between 8.0 and 72.0, got {}",
            size
        ));
    }
    Ok(size)
}

fn update_alacritty_config(size: f32) -> Result<(), String> {
    let home = env::var("HOME").map_err(|_| "HOME environment variable not set".to_string())?;
    let config_path = format!("{}/.config/alacritty/alacritty.toml", home);

    // Read the current config
    let mut file = fs::File::open(&config_path)
        .map_err(|e| format!("Failed to open alacritty config: {}", e))?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .map_err(|e| format!("Failed to read alacritty config: {}", e))?;

    // Parse as TOML
    let mut config: toml::Value = toml::from_str(&contents)
        .map_err(|e| format!("Failed to parse alacritty config: {}", e))?;

    // Update the font size
    if let Some(font) = config.get_mut("font")
        && let Some(font_table) = font.as_table_mut()
    {
        font_table.insert("size".to_string(), toml::Value::Float(size as f64));
    }

    // Write back to file
    let new_contents = toml::to_string_pretty(&config)
        .map_err(|e| format!("Failed to serialize config: {}", e))?;
    let mut file = fs::File::create(&config_path)
        .map_err(|e| format!("Failed to open config for writing: {}", e))?;
    file.write_all(new_contents.as_bytes())
        .map_err(|e| format!("Failed to write config: {}", e))?;

    Ok(())
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    let (repo_path, geometry, web_port) = match validate_args(&args) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("{}", e);
            eprintln!("Example: vnccc /home/user/myproject 1024x1024 8080");
            std::process::exit(1);
        }
    };

    let display = find_available_display();
    let vnc_port = 5900 + display;
    let ws_port = 6080; // websockify port for noVNC

    println!("Starting VNC on display :{} (port {})", display, vnc_port);
    let mut vnc_proc = start_vnc_server(display, &geometry);

    thread::sleep(Duration::from_millis(500));

    match vnc_proc.try_wait() {
        Ok(Some(status)) => {
            eprintln!("VNC server exited unexpectedly: {}", status);
            std::process::exit(1);
        }
        Ok(None) => {}
        Err(e) => {
            eprintln!("Error checking VNC: {}", e);
            std::process::exit(1);
        }
    }

    println!("Starting websockify on port {}", ws_port);
    let websockify_proc = start_websockify(vnc_port, ws_port);

    thread::sleep(Duration::from_millis(300));

    println!("Starting ratpoison window manager");
    let wm_proc = start_window_manager(display);
    // Window manager runs for app lifetime, intentionally not waiting
    mem::forget(wm_proc);
    thread::sleep(Duration::from_millis(200));

    let terminal = find_terminal();
    println!("Starting {} with agent in {}", terminal, repo_path);

    // Spawn terminal monitor task that auto-restarts on exit
    let repo_path_clone = repo_path.clone();
    let geometry_clone = geometry.to_string();
    tokio::spawn(async move {
        loop {
            let mut term_proc =
                start_terminal_with_agent(display, &repo_path_clone, terminal, &geometry_clone);
            println!("Terminal started (pid: {:?})", term_proc.id());

            // Wait for terminal to exit
            match term_proc.wait() {
                Ok(status) => {
                    println!("Terminal exited with status: {} - restarting...", status);
                }
                Err(e) => {
                    eprintln!("Error waiting for terminal: {} - restarting...", e);
                }
            }

            // Brief delay before restart
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    });

    let state = Arc::new(AppState { display });

    // Wrap processes for cleanup
    let processes = Arc::new(Mutex::new(Processes {
        vnc: vnc_proc,
        websockify: websockify_proc,
    }));
    let processes_clone = processes.clone();

    let app = Router::new()
        .route("/", get(index_handler))
        .route("/prompt", get(prompt_ws_handler))
        .route("/api/font-size", post(font_size_handler))
        .route(
            "/favicon.ico",
            get(|| async {
                // Redirect /static/favicon.ico to /favicon.ico
                axum::response::Redirect::permanent("/static/favicon.ico")
            }),
        )
        .nest_service("/static", ServeDir::new("static"))
        .with_state(state);

    println!();
    println!("=== vncaa running ===");
    println!("Web UI: http://localhost:{}", web_port);
    println!("VNC websocket: ws://localhost:{}", ws_port);
    println!();

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", web_port))
        .await
        .unwrap();

    // Run server with graceful shutdown on Ctrl+C
    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            let _ = signal::ctrl_c().await;
            println!("\nShutting down...");
            let mut procs = processes_clone.lock().await;
            let _ = procs.vnc.kill();
            let _ = procs.websockify.kill();
            println!("Cleanup complete");
        })
        .await
        .unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_terminal() {
        assert_eq!(find_terminal(), "alacritty");
    }

    #[test]
    fn test_validate_args_missing_repo_path() {
        let args = vec!["vnccc".to_string()];
        let result = validate_args(&args);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage"));
    }

    #[test]
    fn test_validate_args_with_defaults() {
        let temp_dir = std::env::temp_dir();
        let args = vec!["vnccc".to_string(), temp_dir.to_str().unwrap().to_string()];
        let result = validate_args(&args);
        assert!(result.is_ok());
        let (repo_path, geometry, web_port) = result.unwrap();
        assert_eq!(repo_path, temp_dir.to_str().unwrap());
        assert_eq!(geometry, "1024x1024");
        assert_eq!(web_port, 8080);
    }

    #[test]
    fn test_validate_args_with_custom_values() {
        let temp_dir = std::env::temp_dir();
        let args = vec![
            "vnccc".to_string(),
            temp_dir.to_str().unwrap().to_string(),
            "800x600".to_string(),
            "9090".to_string(),
        ];
        let result = validate_args(&args);
        assert!(result.is_ok());
        let (_, geometry, web_port) = result.unwrap();
        assert_eq!(geometry, "800x600");
        assert_eq!(web_port, 9090);
    }

    #[test]
    fn test_validate_args_nonexistent_path() {
        let args = vec!["vnccc".to_string(), "/nonexistent/path/12345".to_string()];
        let result = validate_args(&args);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("does not exist"));
    }

    #[test]
    fn test_find_available_display_returns_valid_number() {
        let display = find_available_display();
        assert!((1..100).contains(&display));
    }

    #[test]
    fn test_validate_font_size_valid() {
        assert_eq!(validate_font_size(12.0), Ok(12.0));
        assert_eq!(validate_font_size(8.0), Ok(8.0));
        assert_eq!(validate_font_size(72.0), Ok(72.0));
        assert_eq!(validate_font_size(20.5), Ok(20.5));
    }

    #[test]
    fn test_validate_font_size_too_small() {
        let result = validate_font_size(7.9);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("between 8.0 and 72.0"));
    }

    #[test]
    fn test_validate_font_size_too_large() {
        let result = validate_font_size(72.1);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("between 8.0 and 72.0"));
    }

    #[test]
    fn test_validate_font_size_invalid() {
        let result = validate_font_size(f32::NAN);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("valid number"));
    }
}
