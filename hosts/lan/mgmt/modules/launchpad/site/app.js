(function () {
  "use strict";

  var DATA = [
    {
      key: "security", label: "Security", color: "#ff4d6d",
      services: [
        { name: "AdGuard Home", desc: "DNS filtering for the LAN", href: "https://adguard.mgmt.lan" },
      ],
    },
    {
      key: "observability", label: "Observability", color: "#4dd8ff",
      services: [
        { name: "Grafana", desc: "Metrics + log dashboards (Prometheus + Loki)", href: "https://grafana.mgmt.lan" },
        { name: "Logs (Explore)", desc: "Search the fleet's journals in Loki", href: "https://grafana.mgmt.lan/explore" },
        { name: "Alertmanager", desc: "Fired alerts - view, silence, routing", href: "https://alerts.mgmt.lan" },
        { name: "ntfy", desc: "Push alerts - subscribe to /homelab-alerts", href: "https://ntfy.mgmt.lan" },
        { name: "Uptime Kuma", desc: "Service uptime monitoring", href: "https://status.mgmt.lan" },
        { name: "ntopng", desc: "Network traffic analysis", href: "https://ntop.mgmt.lan" },
      ],
    },
    {
      key: "infrastructure", label: "Infrastructure", color: "#ffb84d",
      services: [
        { name: "NetBox", desc: "IPAM & network documentation", href: "https://netbox.mgmt.lan" },
        { name: "Forgejo", desc: "Git hosting", href: "https://git.mgmt.lan" },
        { name: "Snipe-IT", desc: "Asset inventory", href: "https://assets.mgmt.lan" },
        { name: "Root CA cert", desc: "Install on devices to trust *.mgmt.lan", href: "https://ca.mgmt.lan/root.crt" },
        { name: "Nix cache pubkey", desc: "Binary cache at https://cache.mgmt.lan", href: "https://cache.mgmt.lan/pubkey" },
      ],
    },
    {
      key: "media", label: "Media", color: "#b98bff",
      services: [
        { name: "Jellyfin", desc: "Media streaming", href: "http://192.168.1.189:8096" },
        { name: "Radarr", desc: "Movies", href: "http://192.168.1.189:7878" },
        { name: "Sonarr", desc: "TV shows", href: "http://192.168.1.189:8989" },
        { name: "Prowlarr", desc: "Indexer manager", href: "http://192.168.1.189:9696" },
        { name: "Bazarr", desc: "Subtitles", href: "http://192.168.1.189:6767" },
        { name: "NZBGet", desc: "Usenet downloader", href: "http://192.168.1.189:6789" },
        { name: "Kavita", desc: "Books, comics & manga", href: "http://192.168.1.189:5000" },
        { name: "Newspaper", desc: "Morning e-ink RSS edition", href: "https://news.mgmt.lan" },
      ],
    },
    {
      key: "lab", label: "Lab", color: "#39ff9d",
      services: [
        { name: "Guacamole", desc: "Browser remote-desktop gateway (RDP/VNC/SSH)", href: "http://192.168.1.217:8080/guacamole/" },
        { name: "Cockpit", desc: "playground libvirt VMs - power/console + host health", href: "https://cockpit.mgmt.lan" },
      ],
    },
    {
      key: "games", label: "Games", color: "#ff9de2",
      services: [
        { name: "All the Mons", desc: "ATMons modpack server - connect to 192.168.1.26:25565", href: "https://www.curseforge.com/minecraft/modpacks/all-the-mons" },
      ],
    },
  ];

  var totalServices = DATA.reduce(function (n, cat) { return n + cat.services.length; }, 0);
  document.getElementById("status-count").textContent = totalServices + " services orbiting";

  // ---------- clock ----------
  var clockEl = document.getElementById("clock");
  function tick() {
    clockEl.textContent = new Date().toLocaleTimeString([], {
      hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: true,
    });
  }
  tick();
  setInterval(tick, 1000);

  // ---------- starfield (static, drawn once) ----------
  (function stars() {
    var canvas = document.getElementById("stars");
    var ctx = canvas.getContext("2d");
    function draw() {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
      ctx.fillStyle = "#03060d";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      var count = Math.floor((canvas.width * canvas.height) / 4500);
      for (var i = 0; i < count; i++) {
        var x = Math.random() * canvas.width;
        var y = Math.random() * canvas.height;
        var r = Math.random() * 1.1 + 0.2;
        ctx.fillStyle = "rgba(200, 225, 255, " + (Math.random() * 0.6 + 0.15) + ")";
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    draw();
    var t;
    window.addEventListener("resize", function () {
      clearTimeout(t);
      t = setTimeout(draw, 200);
    });
  })();

  // ---------- fallback grouped list ----------
  var fallback = document.getElementById("fallback-list");
  (function buildFallback() {
    var html = '<h1 class="fl-title">alcove</h1><p class="fl-tagline">everything, in orbit</p>';
    DATA.forEach(function (cat) {
      html += '<section class="category" style="--cat-color:' + cat.color + '">';
      html += "<h2>" + cat.label + "</h2><div class=\"tiles\">";
      cat.services.forEach(function (s) {
        html +=
          '<a class="tile" href="' + s.href + '">' +
          '<span class="tile-name">' + s.name + "</span>" +
          '<span class="tile-desc">' + s.desc + "</span></a>";
      });
      html += "</div></section>";
    });
    fallback.innerHTML = html;
  })();

  // ---------- orbit engine ----------
  var stage = document.getElementById("orbit-stage");
  var svg = document.getElementById("orbit-svg");
  var tooltip = document.getElementById("tooltip");
  var SVGNS = "http://www.w3.org/2000/svg";
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var mq = window.matchMedia("(min-width: 720px)");

  var rings = []; // { cat, radius, dir, speed, nodes: [{el, spoke, angleOffset}] }
  var center = { x: 0, y: 0 };
  var t = 0;
  var built = false;

  function buildOrbit() {
    if (built) return;
    built = true;

    DATA.forEach(function (cat, ringIndex) {
      var ringGlow = document.createElementNS(SVGNS, "circle");
      ringGlow.setAttribute("class", "ring-glow");
      ringGlow.setAttribute("stroke", cat.color);
      svg.appendChild(ringGlow);

      var ringGuide = document.createElementNS(SVGNS, "circle");
      ringGuide.setAttribute("class", "ring-guide");
      ringGuide.setAttribute("stroke", cat.color);
      svg.appendChild(ringGuide);

      var ring = {
        cat: cat,
        radius: 0,
        dir: ringIndex % 2 === 0 ? 1 : -1,
        speed: 0.09 / (ringIndex + 1.4),
        glow: ringGlow,
        guide: ringGuide,
        nodes: [],
      };

      cat.services.forEach(function (svc, i) {
        var spoke = document.createElementNS(SVGNS, "line");
        spoke.setAttribute("class", "spoke");
        spoke.setAttribute("stroke", cat.color);
        svg.appendChild(spoke);

        var chord = null;
        if (cat.services.length > 1) {
          chord = document.createElementNS(SVGNS, "line");
          chord.setAttribute("class", "chord");
          chord.setAttribute("stroke", cat.color);
          svg.appendChild(chord);
        }

        var a = document.createElement("a");
        a.className = "node";
        a.href = svc.href;
        a.style.setProperty("--node-color", cat.color);
        a.style.animationDelay = -(Math.random() * 4).toFixed(2) + "s";
        a.textContent = svc.name;
        a.setAttribute("aria-label", svc.name + " - " + svc.desc);

        function show() {
          tooltip.innerHTML =
            '<span class="t-name">' + svc.name + "</span>" +
            '<span class="t-desc">' + svc.desc + "</span>";
          tooltip.style.setProperty("--tooltip-color", cat.color);
          var r = a.getBoundingClientRect();
          var top = r.top - 10;
          var left = Math.min(Math.max(r.left + r.width / 2, 130), window.innerWidth - 130);
          tooltip.style.left = left + "px";
          tooltip.style.top = top + "px";
          tooltip.style.transform = "translate(-50%, -100%)";
          tooltip.classList.add("visible");
        }
        function hide() {
          tooltip.classList.remove("visible");
        }
        a.addEventListener("mouseenter", show);
        a.addEventListener("focus", show);
        a.addEventListener("mouseleave", hide);
        a.addEventListener("blur", hide);

        stage.appendChild(a);
        ring.nodes.push({
          el: a,
          spoke: spoke,
          chord: chord,
          angleOffset: (Math.PI * 2 * i) / cat.services.length,
        });
      });

      rings.push(ring);
    });
  }

  function layout() {
    var w = stage.clientWidth;
    var h = stage.clientHeight;
    center.x = w / 2;
    center.y = h / 2;

    var maxR = Math.min(w, h) * 0.48;
    var minR = Math.min(w, h) * 0.24;
    var gap = rings.length > 1 ? (maxR - minR) / (rings.length - 1) : 0;

    rings.forEach(function (ring, i) {
      ring.radius = minR + gap * i;
      ring.glow.setAttribute("cx", center.x);
      ring.glow.setAttribute("cy", center.y);
      ring.glow.setAttribute("r", ring.radius);
      ring.guide.setAttribute("cx", center.x);
      ring.guide.setAttribute("cy", center.y);
      ring.guide.setAttribute("r", ring.radius);
    });
  }

  function render() {
    rings.forEach(function (ring) {
      var pts = [];
      ring.nodes.forEach(function (node) {
        var angle = node.angleOffset + t * ring.speed * ring.dir;
        var x = center.x + Math.cos(angle) * ring.radius;
        var y = center.y + Math.sin(angle) * ring.radius;
        node.el.style.transform = "translate(" + x + "px," + y + "px) translate(-50%,-50%)";
        node.spoke.setAttribute("x1", center.x);
        node.spoke.setAttribute("y1", center.y);
        node.spoke.setAttribute("x2", x);
        node.spoke.setAttribute("y2", y);
        pts.push({ x: x, y: y });
      });
      ring.nodes.forEach(function (node, i) {
        if (!node.chord) return;
        var next = pts[(i + 1) % pts.length];
        node.chord.setAttribute("x1", pts[i].x);
        node.chord.setAttribute("y1", pts[i].y);
        node.chord.setAttribute("x2", next.x);
        node.chord.setAttribute("y2", next.y);
      });
    });
  }

  var lastTs = null;
  function frame(ts) {
    if (!mq.matches) {
      lastTs = null;
      requestAnimationFrame(frame);
      return;
    }
    if (lastTs === null) lastTs = ts;
    var dt = (ts - lastTs) / 1000;
    lastTs = ts;
    if (!reduceMotion) t += dt;
    render();
    requestAnimationFrame(frame);
  }

  function setNarrow(isNarrow) {
    document.body.classList.toggle("narrow", isNarrow);
  }

  function initOrbit() {
    if (!mq.matches) return;
    buildOrbit();
    layout();
    render();
  }

  setNarrow(!mq.matches);
  initOrbit();
  requestAnimationFrame(frame);

  mq.addEventListener("change", function (e) {
    setNarrow(!e.matches);
    if (e.matches) initOrbit();
  });

  var resizeT;
  window.addEventListener("resize", function () {
    clearTimeout(resizeT);
    resizeT = setTimeout(function () {
      if (mq.matches) {
        layout();
        render();
      }
    }, 120);
  });
})();
