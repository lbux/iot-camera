use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::fs;

use chrono::Local;

use aws_config::meta::region::RegionProviderChain;
use aws_sdk_s3::{Client, primitives::ByteStream};

#[derive(Clone)]
struct AppState {
    mediamtx_process: Arc<Mutex<Option<Child>>>,
}

async fn start_server(data: web::Data<AppState>) -> impl Responder {
    println!("Received request to start MediaMTX.");
    let mut process_guard = data.mediamtx_process.lock().unwrap();
    if process_guard.is_some() {
        println!("MediaMTX is already running.");
        return HttpResponse::Conflict().body("MediaMTX server is already running.");
    }

    let mediamtx_path = "/usr/local/bin/mediamtx";
    let config_path = "/etc/mediamtx/mediamtx.yml";

    match Command::new(mediamtx_path)
        .arg(config_path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => {
            *process_guard = Some(child);
            println!("MediaMTX started successfully.");
            HttpResponse::Ok().body("MediaMTX server started.")
        }
        Err(e) => {
            println!("Failed to start MediaMTX: {}", e);
            HttpResponse::InternalServerError().body(format!("Failed to start MediaMTX: {}", e))
        }
    }
}

async fn stop_server(data: web::Data<AppState>) -> impl Responder {
    println!("Received request to stop MediaMTX.");
    let mut process_guard = data.mediamtx_process.lock().unwrap();

    if let Some(mut child) = process_guard.take() {
        match child.kill() {
            Ok(_) => {
                println!("MediaMTX main process killed.");
                
                // Use a system command to kill any remaining MediaMTX related processes
                let cleanup_command = Command::new("pkill")
                    .args(["-f", "mediamtx"])
                    .output();

                match cleanup_command {
                    Ok(output) => {
                        println!("Cleanup command executed.");
                        println!("Cleanup stdout: {}", String::from_utf8_lossy(&output.stdout));
                        println!("Cleanup stderr: {}", String::from_utf8_lossy(&output.stderr));

                        if output.status.success() {
                            println!("All MediaMTX processes terminated successfully.");
                            HttpResponse::Ok().body("MediaMTX server stopped and cleaned up.")
                        } else {
                            println!(
                                "Cleanup command failed: {}",
                                String::from_utf8_lossy(&output.stderr)
                            );
                            HttpResponse::InternalServerError()
                                .body("MediaMTX server stopped, but cleanup failed.")
                        }
                    }
                    Err(e) => {
                        println!("Failed to execute cleanup command: {}", e);
                        HttpResponse::InternalServerError()
                            .body("MediaMTX server stopped, but cleanup command failed.")
                    }
                }
            }
            Err(e) => {
                println!("Failed to kill MediaMTX main process: {}", e);
                HttpResponse::InternalServerError().body(format!("Failed to stop MediaMTX: {}", e))
            }
        }
    } else {
        println!("MediaMTX is not running.");
        HttpResponse::Conflict().body("MediaMTX server is not running.")
    }
}

async fn take_screenshot() -> impl Responder {
    println!("Received request to take a screenshot.");

    // Generate a unique filename based on the current timestamp
    let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S").to_string();
    let screenshot_path = format!("/tmp/screenshot_{}.jpg", timestamp);
    let rtsp_url = "rtsp://localhost:8554/cam";

    println!("RTSP URL: {}", rtsp_url);
    println!("Screenshot will be saved to: {}", screenshot_path);

    let command = Command::new("ffmpeg")
        .args([
            "-i",
            rtsp_url,
            "-vframes",
            "1",
            "-q:v",
            "2",
            &screenshot_path,
        ])
        .output();

    match command {
        Ok(output) => {
            println!("FFmpeg command executed.");
            println!("FFmpeg stdout: {}", String::from_utf8_lossy(&output.stdout));
            println!("FFmpeg stderr: {}", String::from_utf8_lossy(&output.stderr));

            if output.status.success() {
                println!("Screenshot saved successfully to {}", screenshot_path);

                // S3 upload logic
                let region_provider = RegionProviderChain::default_provider().or_else("us-east-1");
                let config = aws_config::from_env().region(region_provider).load().await;
                let client = Client::new(&config);

                let bucket_name = "smart-doorbell-bucket";
                let key = format!("screenshots/{}.jpg", timestamp);

                match fs::read(&screenshot_path) {
                    Ok(file_bytes) => {
                        match client
                            .put_object()
                            .bucket(bucket_name)
                            .key(&key)
                            .body(ByteStream::from(file_bytes))
                            .send()
                            .await
                        {
                            Ok(_) => {
                                println!("Screenshot uploaded successfully to S3.");

                                let s3_url = format!(
                                    "https://{}.s3.{}.amazonaws.com/{}",
                                    bucket_name, "us-east-1", key
                                );                                

                                println!("Screenshot URL: {}", s3_url);

                                HttpResponse::Ok().json({
                                    serde_json::json!({
                                        "message": "Screenshot uploaded successfully",
                                        "url": s3_url,
                                    })
                                })
                            }
                            Err(e) => {
                                println!("Failed to upload screenshot to S3: {}", e);
                                HttpResponse::InternalServerError().body(format!(
                                    "Screenshot saved locally to {} but failed to upload to S3: {}",
                                    screenshot_path, e
                                ))
                            }
                        }
                    }
                    Err(e) => {
                        println!("Failed to read screenshot file: {}", e);
                        HttpResponse::InternalServerError().body(format!(
                            "Screenshot saved locally to {} but failed to read for upload: {}",
                            screenshot_path, e
                        ))
                    }
                }
            } else {
                println!(
                    "FFmpeg failed with error: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
                HttpResponse::InternalServerError()
                    .body(format!("FFmpeg error: {}", String::from_utf8_lossy(&output.stderr)))
            }
        }
        Err(e) => {
            println!("Failed to execute FFmpeg: {}", e);
            HttpResponse::InternalServerError().body(format!("Failed to execute FFmpeg: {}", e))
        }
    }
}


#[actix_web::main]
async fn main() -> std::io::Result<()> {
    println!("Starting the server...");

    let state = web::Data::new(AppState {
        mediamtx_process: Arc::new(Mutex::new(None)),
    });

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .route("/start", web::post().to(start_server))
            .route("/stop", web::post().to(stop_server))
            .route("/screenshot", web::post().to(take_screenshot))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}