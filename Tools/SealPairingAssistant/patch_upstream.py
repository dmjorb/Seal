from __future__ import annotations

import pathlib
import sys

UPSTREAM_COMMIT = "e3abb341b73a4fbeb96cdfc5e6652687e4bee130"
SEAL_PAIRING_FILE = "SealPairing.mobiledevicepairing"


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{description}: expected exactly one upstream match, found {count}")
    return text.replace(old, new, 1)


def insert_after_once(text: str, anchor: str, addition: str, description: str) -> str:
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"{description}: expected exactly one upstream match, found {count}")
    return text.replace(anchor, anchor + addition, 1)


def patch_cargo(path: pathlib.Path) -> None:
    text = path.read_text(encoding="utf-8")
    anchor = 'rust-i18n = "3"\n'
    addition = 'raw-window-handle = "0.6.2"\n'
    if addition not in text:
        text = insert_after_once(text, anchor, addition, "raw-window-handle dependency")
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_main(path: pathlib.Path) -> None:
    text = path.read_text(encoding="utf-8")
    app_anchor = '            supported_apps.insert("Ksign".to_string(), "pairingFile.plist".to_string());\n'
    if text.count(app_anchor) != 2:
        raise RuntimeError(f"supported-app anchor drifted: expected 2, found {text.count(app_anchor)}")
    app_replacement = app_anchor + (
        '            supported_apps.insert("Seal".to_string(), '
        f'"{SEAL_PAIRING_FILE}".to_string());\n'
    )
    text = text.replace(app_anchor, app_replacement, 2)

    font_function_end = """    }\n}\n\nfn main() {\n"""
    seal_theme = """    }\n}\n\n#[cfg(windows)]\nfn setup_windows_backdrop(cc: &eframe::CreationContext<'_>) {\n    use raw_window_handle::{HasWindowHandle, RawWindowHandle};\n    use std::ffi::c_void;\n\n    #[link(name = \"dwmapi\")]\n    unsafe extern \"system\" {\n        fn DwmSetWindowAttribute(\n            hwnd: *mut c_void,\n            dw_attribute: u32,\n            pv_attribute: *const c_void,\n            cb_attribute: u32,\n        ) -> i32;\n    }\n\n    let Ok(window_handle) = cc.window_handle() else { return; };\n    let RawWindowHandle::Win32(handle) = window_handle.as_raw() else { return; };\n\n    const DWMWA_USE_IMMERSIVE_DARK_MODE: u32 = 20;\n    const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;\n    const DWMWA_SYSTEMBACKDROP_TYPE: u32 = 38;\n    const DWMWCP_ROUND: i32 = 2;\n    const DWMSBT_TRANSIENTWINDOW: i32 = 3;\n\n    let hwnd = handle.hwnd.get() as *mut c_void;\n    let light_mode: i32 = 0;\n    let corner = DWMWCP_ROUND;\n    let backdrop = DWMSBT_TRANSIENTWINDOW;\n    unsafe {\n        let _ = DwmSetWindowAttribute(\n            hwnd,\n            DWMWA_USE_IMMERSIVE_DARK_MODE,\n            &light_mode as *const _ as *const c_void,\n            std::mem::size_of_val(&light_mode) as u32,\n        );\n        let _ = DwmSetWindowAttribute(\n            hwnd,\n            DWMWA_WINDOW_CORNER_PREFERENCE,\n            &corner as *const _ as *const c_void,\n            std::mem::size_of_val(&corner) as u32,\n        );\n        let _ = DwmSetWindowAttribute(\n            hwnd,\n            DWMWA_SYSTEMBACKDROP_TYPE,\n            &backdrop as *const _ as *const c_void,\n            std::mem::size_of_val(&backdrop) as u32,\n        );\n    }\n}\n\n#[cfg(not(windows))]\nfn setup_windows_backdrop(_cc: &eframe::CreationContext<'_>) {}\n\nfn setup_seal_theme(ctx: &egui::Context) {\n    let seal_blue = Color32::from_rgb(0, 122, 255);\n    let seal_blue_soft = Color32::from_rgb(226, 239, 255);\n    let mut visuals = egui::Visuals::light();\n    visuals.panel_fill = Color32::from_rgba_unmultiplied(244, 247, 251, 226);\n    visuals.window_fill = Color32::from_rgba_unmultiplied(255, 255, 255, 220);\n    visuals.extreme_bg_color = Color32::from_rgba_unmultiplied(255, 255, 255, 210);\n    visuals.faint_bg_color = Color32::from_rgba_unmultiplied(255, 255, 255, 150);\n    visuals.selection.bg_fill = seal_blue;\n    visuals.hyperlink_color = seal_blue;\n    visuals.widgets.active.bg_fill = seal_blue;\n    visuals.widgets.active.fg_stroke.color = Color32::WHITE;\n    visuals.widgets.hovered.bg_fill = seal_blue_soft;\n    visuals.widgets.hovered.fg_stroke.color = Color32::from_rgb(0, 94, 204);\n    visuals.widgets.inactive.bg_fill = Color32::from_rgba_unmultiplied(255, 255, 255, 184);\n    visuals.widgets.inactive.weak_bg_fill = Color32::from_rgba_unmultiplied(255, 255, 255, 148);\n    visuals.window_corner_radius = egui::CornerRadius::same(24);\n    visuals.menu_corner_radius = egui::CornerRadius::same(16);\n    visuals.widgets.noninteractive.corner_radius = egui::CornerRadius::same(14);\n    visuals.widgets.inactive.corner_radius = egui::CornerRadius::same(14);\n    visuals.widgets.hovered.corner_radius = egui::CornerRadius::same(14);\n    visuals.widgets.active.corner_radius = egui::CornerRadius::same(14);\n    visuals.widgets.open.corner_radius = egui::CornerRadius::same(14);\n    ctx.set_visuals(visuals);\n\n    let mut style = (*ctx.style()).clone();\n    style.spacing.item_spacing = egui::vec2(10.0, 10.0);\n    style.spacing.button_padding = egui::vec2(14.0, 9.0);\n    ctx.set_style(style);\n}\n\nfn main() {\n"""
    text = replace_once(text, font_function_end, seal_theme, "Seal theme injection")
    options_anchor = "    let mut options = eframe::NativeOptions::default();\n"
    options_replacement = """    let mut options = eframe::NativeOptions::default();\n    options.viewport = options\n        .viewport\n        .clone()\n        .with_inner_size([760.0, 780.0])\n        .with_min_inner_size([640.0, 680.0])\n        .with_transparent(true);\n"""
    text = replace_once(text, options_anchor, options_replacement, "native viewport setup")
    text = replace_once(
        text,
        '&format!("idevice pair v{}", env!("CARGO_PKG_VERSION")),\n',
        '"Seal 配对助手",\n',
        "native window title",
    )
    creation_anchor = """        Box::new(|cc| {\n            setup_custom_fonts(&cc.egui_ctx);\n            Ok(Box::new(app))\n        }),\n"""
    creation_replacement = """        Box::new(|cc| {\n            setup_custom_fonts(&cc.egui_ctx);\n            setup_seal_theme(&cc.egui_ctx);\n            setup_windows_backdrop(cc);\n            Ok(Box::new(app))\n        }),\n"""
    text = replace_once(text, creation_anchor, creation_replacement, "Seal visual setup")
    secret_preview = """                            let p_background_color = match ctx.theme() {\n                                egui::Theme::Dark => Color32::BLACK,\n                                egui::Theme::Light => Color32::LIGHT_GRAY,\n                            };\n                            egui::frame::Frame::new().corner_radius(10).inner_margin(10).fill(p_background_color).show(ui, |ui| {\n                                ui.label(RichText::new(&pairing_file).monospace());\n                            });\n"""
    secure_preview = """                            egui::frame::Frame::new()\n                                .corner_radius(16)\n                                .inner_margin(14)\n                                .fill(Color32::from_rgba_unmultiplied(255, 255, 255, 150))\n                                .show(ui, |ui| {\n                                    ui.strong(t!(\"pairing_material_hidden\"));\n                                    ui.label(RichText::new(t!(\"pairing_material_hidden_help\")).weak());\n                                });\n"""
    text = replace_once(text, secret_preview, secure_preview, "pairing secret redaction")

    app_tail = "        });\n    }\n}\n"
    if not text.endswith(app_tail):
        raise RuntimeError("eframe App tail drifted")
    text = text[: -len(app_tail)] + """        });\n    }\n\n    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {\n        [0.0, 0.0, 0.0, 0.0]\n    }\n}\n"""
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_locale(path: pathlib.Path, expected: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(text, expected, replacement, f"locale {path.name}")
    path.write_text(text, encoding="utf-8", newline="\n")


def append_locale_keys(path: pathlib.Path, entries: str) -> None:
    text = path.read_text(encoding="utf-8")
    if "pairing_material_hidden = " not in text:
        if not text.endswith("\n"):
            text += "\n"
        text += entries
    path.write_text(text, encoding="utf-8", newline="\n")


def verify(root: pathlib.Path) -> None:
    main = (root / "src" / "main.rs").read_text(encoding="utf-8")
    cargo = (root / "Cargo.toml").read_text(encoding="utf-8")
    required = [
        'supported_apps.insert("Seal".to_string(), "SealPairing.mobiledevicepairing".to_string());',
        "fn setup_seal_theme",
        "fn setup_windows_backdrop",
        "DWMSBT_TRANSIENTWINDOW",
        '"Seal 配对助手"',
        "setup_seal_theme(&cc.egui_ctx);",
        "setup_windows_backdrop(cc);",
        't!("pairing_material_hidden")',
        "GeneratePairingFile",
        "ValidateRemote",
        "EnableWireless",
        "CheckDevMode",
        "AutoMount",
        "InstallPairingFile",
        "PairingMode::Lockdown",
        "PairingMode::RemotePairing",
    ]
    missing = [item for item in required if item not in main]
    if missing:
        raise RuntimeError(f"Seal/upstream feature verification failed: {missing}")
    marker = 'supported_apps.insert("Seal".to_string(), "SealPairing.mobiledevicepairing".to_string());'
    if main.count(marker) != 2:
        raise RuntimeError("Seal must be supported in both pairing modes")
    if 'RichText::new(&pairing_file).monospace()' in main:
        raise RuntimeError("raw pairing material must not be rendered in the UI")
    if 'raw-window-handle = "0.6.2"' not in cargo:
        raise RuntimeError("Windows backdrop dependency missing")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_upstream.py <idevice_pair checkout>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    patch_cargo(root / "Cargo.toml")
    patch_main(root / "src" / "main.rs")
    patch_locale(root / "locales" / "zh-cn.toml", 'app_title = "idevice pair"', 'app_title = "Seal 配对助手"')
    patch_locale(root / "locales" / "en.toml", 'app_title = "idevice pair"', 'app_title = "Seal Pairing Assistant"')
    append_locale_keys(
        root / "locales" / "zh-cn.toml",
        'pairing_material_hidden = "配对信息已安全生成"\n'
        'pairing_material_hidden_help = "敏感密钥内容默认不显示。你仍可保存、验证或直接写入 Seal。"\n',
    )
    append_locale_keys(
        root / "locales" / "en.toml",
        'pairing_material_hidden = "Pairing information generated securely"\n'
        'pairing_material_hidden_help = "Sensitive key material is hidden by default. Saving, validation, and direct install to Seal remain available."\n',
    )
    verify(root)
    print(f"Seal overlay applied to idevice_pair {UPSTREAM_COMMIT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
