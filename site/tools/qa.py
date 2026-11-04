# Dev-only QA harness: serves the project root, loads every chapter at desktop + mobile,
# records console errors and saves screenshots to site/screenshots/.
# Usage: python site/tools/qa.py [--fixtures]   (needs: pip install playwright)
import http.server, socketserver, threading, sys, os, functools, json
from pathlib import Path
from playwright.sync_api import sync_playwright

SITE = Path(__file__).resolve().parents[1]
ROOT = SITE.parent
OUT = SITE / "screenshots"; OUT.mkdir(exist_ok=True)

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass

def serve():
    h = functools.partial(Quiet, directory=str(ROOT))
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", 0), h)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd

SHOTS = [("ch0", "chapter=0"), ("ch1-2023", "step=2023"), ("ch1-2024", "step=2024"), ("ch1-2025", "step=2025"), ("ch1-2026", "step=2026"),
         ("ch2", "chapter=2"), ("ch3", "chapter=3"), ("ch4", "chapter=4"), ("ch5", "chapter=5"), ("ch6", "chapter=6"), ("ch7", "chapter=7")]
SIZES = {"desktop": (1440, 900), "mobile": (390, 844)}

def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    httpd = serve()
    base = f"http://127.0.0.1:{httpd.server_address[1]}/site/index.html"
    errors = []
    checked = 0
    def check(page):
        nonlocal checked
        page.wait_for_function("document.documentElement.classList.contains('is-ready')")
        assert page.evaluate("!Atlas.data.anyFixture"), "Illustrative data in release"
        assert page.evaluate("Object.values(Atlas.data.sectionStatus).every(s => s === 'json')")
        assert page.locator(".missing").count() == 0, "Missing narrative facts"
        assert page.locator(".load-error").count() == 0
        assert page.locator("#fixture-badge").is_hidden()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1"), "Horizontal overflow"
        assert page.locator(".chart-host svg").count() >= 7, "Missing chart"
        assert page.evaluate("Atlas.data.std.use.length >= 3"), "Mix-adjusted series not loaded"
        assert page.evaluate("Atlas.data.experience.bands.length === 4")
        assert "31.0 pp" in page.locator("#panel-frequency").text_content()
        assert "small detectable gain" in page.locator("#panel-stability").text_content()
        assert "182-row discrepancy remains unresolved" in page.locator("#panel-source-audit").text_content()
        assert page.locator("#frequency-table tbody tr").count() == 3
        assert page.locator("#stability-table tbody tr").count() == 2
        assert page.locator("#population-table tbody tr").count() == 4
        checked += 1

    def screenshot(page, name):
        if os.environ.get("ATLAS_SCREENSHOTS") != "0":
            page.screenshot(path=str(OUT / name))

    with sync_playwright() as p:
        try: browser = p.chromium.launch(channel="msedge")
        except Exception: browser = p.chromium.launch()
        for size, (w, h) in SIZES.items():
            ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=1)
            for name, q in SHOTS:
                if only and name not in only: continue
                page = ctx.new_page()
                page.on("pageerror", lambda e: errors.append(f"interactions: PAGEERROR {e}"))
                page.on("console", lambda m: m.type == "error" and errors.append(f"interactions: {m.text}"))
                page.on("console", lambda m, n=name, s=size: m.type == "error" and errors.append(f"{s}/{n}: {m.text}"))
                page.on("pageerror", lambda e, n=name, s=size: errors.append(f"{s}/{n}: PAGEERROR {e}"))
                page.goto(f"{base}?{q}", wait_until="networkidle")
                check(page)
                page.wait_for_timeout(1600)
                screenshot(page, f"{size}-{name}.png")
                page.close()
            ctx.close()
        # dark mode + reduced motion
        ctx = browser.new_context(viewport={"width": 1440, "height": 900}, reduced_motion="reduce")
        for name, q in [("dark-ch2", "chapter=2&theme=dark"), ("dark-ch0", "chapter=0&theme=dark"), ("reduced-ch1", "step=2025&motion=reduce")]:
            if only and name not in only: continue
            page = ctx.new_page()
            page.on("console", lambda m, n=name: m.type == "error" and errors.append(f"{n}: {m.text}"))
            page.on("pageerror", lambda e, n=name: errors.append(f"{n}: PAGEERROR {e}"))
            page.goto(f"{base}?{q}", wait_until="networkidle")
            check(page)
            page.wait_for_timeout(2000)
            screenshot(page, f"desktop-{name}.png")
            page.close()
        page = ctx.new_page()
        page.goto(f"{base}?chapter=2&motion=reduce", wait_until="networkidle")
        check(page)
        handle = page.locator(".scrub-handle")
        handle.focus()
        handle.press("Home")
        assert handle.get_attribute("aria-valuenow") == "2023"
        handle.press("ArrowRight")
        assert handle.get_attribute("aria-valuenow") == "2024"
        page.locator("#trust-mode button[data-value=std]").click()
        assert "mix-adjusted" in page.locator("#trust-table caption").text_content()
        assert page.locator(".gap-wedge").count() == 0, "Invalid cross-population gap"
        for panel in ["panel-frequency", "panel-stability", "panel-source-audit"]:
            details = page.locator(f"#{panel} details")
            details.locator("summary").focus()
            page.keyboard.press("Enter")
            assert details.get_attribute("open") is not None, "Follow-up evidence is not keyboard accessible"
            assert details.locator("table").first.is_visible()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        page.locator("#theme-toggle").click()
        assert page.locator("html").get_attribute("data-theme") == "dark"
        for button in page.locator("#model-outcome button").all():
            button.click()
            for feature in page.locator("#model-fs button").all():
                feature.click()
                for scheme in page.locator("#model-scheme option").evaluate_all("(els) => els.map(e => e.value)"):
                    if page.locator("#model-scheme").is_visible():
                        page.locator("#model-scheme").select_option(scheme)
                    assert page.locator("#model-duel .mrow").count() > 0, "Empty model comparison"
        page.locator("#seg-list button").last.click()
        assert page.locator("#seg-list button").last.get_attribute("aria-pressed") == "true"
        tool = page.locator("#net-chart .nnode").first
        tool.focus()
        tool.press("Enter")
        assert page.locator("#net-chart svg").get_attribute("class").endswith("is-isolating")
        tool.press("Escape")
        assert not page.locator("#net-chart svg").get_attribute("class").endswith("is-isolating")
        page.close()
        missing = ctx.new_page()
        missing.route("**/segments.json", lambda route: route.abort())
        missing.goto(base, wait_until="networkidle")
        missing.wait_for_selector(".load-error")
        assert missing.locator(".load-error").get_attribute("role") == "alert"
        assert missing.locator("#seg-chart").count() == 0, "Missing data must fail closed"
        missing.close()
        ctx.close(); browser.close()
    httpd.shutdown()
    print(json.dumps({"pages_checked": checked, "interaction_checks": "passed",
                      "missing_data_check": "passed", "console_errors": errors}, indent=1))
    if errors:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
