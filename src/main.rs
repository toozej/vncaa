use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    extract::State,
    response::{Html, IntoResponse},
    routing::get,
    Router,
};
use std::env;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use futures::StreamExt;
use tokio::signal;
use tokio::sync::Mutex;

struct AppState {
    display: u32,
}

struct Processes {
    vnc: Child,
    websockify: Child,
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
            "-geometry", geometry,
            "-depth", "24",
            "-SecurityTypes", "None",
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
                    "-geometry", geometry,
                    "-depth", "24",
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

fn find_terminal() -> &'static str {
    "alacritty"
}

fn start_terminal_with_claude(display: u32, repo_path: &str, terminal: &str, geometry: &str) -> Child {
    let display_env = format!(":{}", display);
    let claude_cmd = format!("cd {} && claude", repo_path);

    let mut cmd = Command::new(terminal);
    cmd.env("DISPLAY", &display_env);

    match terminal {
        "wezterm" => {
            cmd.args(["start", "--always-new-process", "--", "bash", "-c", &claude_cmd]);
        }
        "alacritty" => {
            cmd.args(["-e", "bash", "-c", &claude_cmd]);
        }
        "kitty" => {
            cmd.args(["--start-as", "fullscreen", "bash", "-c", &claude_cmd]);
        }
        "xterm" => {
            cmd.args([
                "-maximized",
                "-fa", "Monospace",
                "-fs", "14",
                "-bg", "black",
                "-fg", "white",
                "-e", "bash", "-c", &claude_cmd
            ]);
        }
        "urxvt" => {
            cmd.args(["-geometry", geometry, "-e", "bash", "-c", &claude_cmd]);
        }
        "st" => {
            cmd.args(["-e", "bash", "-c", &claude_cmd]);
        }
        _ => {
            cmd.args(["-e", "bash", "-c", &claude_cmd]);
        }
    }

    cmd.spawn().expect("Failed to start terminal")
}

fn send_text_to_display(display: u32, text: &str) {
    // Use xdotool to type text into the focused window on the display
    let display_env = format!(":{}", display);

    // Type the text and press Enter
    let _ = Command::new("xdotool")
        .env("DISPLAY", &display_env)
        .args(["type", "--clearmodifiers", text])
        .status();

    let _ = Command::new("xdotool")
        .env("DISPLAY", &display_env)
        .args(["key", "Return"])
        .status();
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
    while let Some(msg) = socket.next().await {
        if let Ok(Message::Text(text)) = msg {
            // Use xdotool to type into the X display
            send_text_to_display(display, &text);
        }
    }
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: vnccc <repo-path> [geometry] [web-port]");
        eprintln!("Example: vnccc /home/user/myproject 1024x1024 8080");
        std::process::exit(1);
    }

    let repo_path = args[1].clone();
    let geometry = args.get(2).map(|s| s.as_str()).unwrap_or("1024x1024");
    let web_port: u16 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(8080);

    if !Path::new(&repo_path).exists() {
        eprintln!("Error: repo path '{}' does not exist", repo_path);
        std::process::exit(1);
    }

    let display = find_available_display();
    let vnc_port = 5900 + display;
    let ws_port = 6080; // websockify port for noVNC

    println!("Starting VNC on display :{} (port {})", display, vnc_port);
    let mut vnc_proc = start_vnc_server(display, geometry);

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

    let terminal = find_terminal();
    println!("Starting {} with claude in {}", terminal, repo_path);

    // Spawn terminal monitor task that auto-restarts on exit
    let repo_path_clone = repo_path.clone();
    let geometry_clone = geometry.to_string();
    tokio::spawn(async move {
        loop {
            let mut term_proc = start_terminal_with_claude(display, &repo_path_clone, terminal, &geometry_clone);
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
        .with_state(state);

    println!();
    println!("=== vnccc running ===");
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
