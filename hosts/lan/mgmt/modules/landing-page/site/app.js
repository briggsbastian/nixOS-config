(function () {
  "use strict";

  // ---------- DATA ----------

  var HOSTS = [
    { name: "mgmt", instance: "192.168.1.222:9100" },
    { name: "media", instance: "192.168.1.189:9100" },
    { name: "hacktop", instance: "192.168.1.26:9100" },
    { name: "cloud1", instance: "10.100.0.1:9100" }
  ];

  var SERVICE_DATA = [
    {
      category: "Security",
      services: [
        { name: "AdGuard Home", desc: "DNS filtering for the LAN", href: "https://adguard.mgmt.lan", probe: "https://adguard.mgmt.lan" }
      ]
    },
    {
      category: "Observability",
      services: [
        { name: "Grafana", desc: "Metrics + log dashboards", href: "https://grafana.mgmt.lan", probe: "https://grafana.mgmt.lan" },
        { name: "Logs (Explore)", desc: "Search fleet journals in Loki", href: "https://grafana.mgmt.lan/explore", probe: "https://grafana.mgmt.lan" },
        { name: "Alertmanager", desc: "Fired alerts, silences, routing", href: "https://alerts.mgmt.lan", probe: "https://alerts.mgmt.lan" },
        { name: "ntfy", desc: "Push alerts — subscribe /homelab-alerts", href: "https://ntfy.mgmt.lan", probe: "https://ntfy.mgmt.lan" },
        { name: "Uptime Kuma", desc: "Service uptime monitoring", href: "https://status.mgmt.lan", probe: "https://status.mgmt.lan" },
        { name: "ntopng", desc: "Network traffic analysis", href: "https://ntop.mgmt.lan", probe: "https://ntop.mgmt.lan" }
      ]
    },
    {
      category: "Infrastructure",
      services: [
        { name: "NetBox", desc: "IPAM & network documentation", href: "https://netbox.mgmt.lan", probe: "https://netbox.mgmt.lan" },
        { name: "Forgejo", desc: "Git hosting", href: "https://git.mgmt.lan", probe: "https://git.mgmt.lan" },
        { name: "Snipe-IT", desc: "Asset inventory", href: "https://assets.mgmt.lan", probe: "https://assets.mgmt.lan" },
        { name: "Budget", desc: "Paycheck-aware expense planner", href: "https://budget.mgmt.lan", probe: "https://budget.mgmt.lan" },
        { name: "Root CA cert", desc: "Trust *.mgmt.lan on devices", href: "https://ca.mgmt.lan/root.crt", probe: "https://ca.mgmt.lan" },
        { name: "Nix cache pubkey", desc: "Binary cache at cache.mgmt.lan", href: "https://cache.mgmt.lan/pubkey", probe: "https://cache.mgmt.lan" }
      ]
    },
    {
      category: "Media",
      services: [
        { name: "Jellyfin", desc: "Media streaming", href: "http://192.168.1.189:8096" },
        { name: "Radarr", desc: "Movies", href: "http://192.168.1.189:7878" },
        { name: "Sonarr", desc: "TV shows", href: "http://192.168.1.189:8989" },
        { name: "Prowlarr", desc: "Indexer manager", href: "http://192.168.1.189:9696" },
        { name: "Bazarr", desc: "Subtitles", href: "http://192.168.1.189:6767" },
        { name: "NZBGet", desc: "Usenet downloader", href: "http://192.168.1.189:6789" },
        { name: "Kavita", desc: "Books, comics & manga", href: "http://192.168.1.189:5000" },
        { name: "Kapowarr", desc: "Comic/manga download manager", href: "https://kapowarr.mgmt.lan", probe: "https://kapowarr.mgmt.lan" },
        { name: "Newspaper", desc: "Morning e-ink RSS edition", href: "https://news.mgmt.lan", probe: "https://news.mgmt.lan" }
      ]
    },
    {
      category: "Games",
      services: [
        { name: "All the Mons", desc: "ATMons — connect 192.168.1.26:25565", href: "https://www.curseforge.com/minecraft/modpacks/all-the-mons" }
      ]
    }
  ];

  // ---------- CLOCK ----------

  var clockEl = document.getElementById("clock");
  function tick() {
    clockEl.textContent = new Date().toLocaleTimeString([], {
      hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: true
    });
  }
  tick();
  setInterval(tick, 1000);

  // ---------- API HELPERS ----------

  var PROM_BASE = "/api/prometheus";
  var AM_BASE = "/api/alertmanager";

  function promQuery(q) {
    return fetch(PROM_BASE + "/api/v1/query?query=" + encodeURIComponent(q))
      .then(function (r) { return r.json(); })
      .then(function (d) { return d.status === "success" ? d.data.result : []; })
      .catch(function () { return []; });
  }

  function promQueryRange(q) {
    return fetch(PROM_BASE + "/api/v1/query?query=" + encodeURIComponent(q))
      .then(function (r) { return r.json(); })
      .then(function (d) { return d.status === "success" ? d.data.result : []; })
      .catch(function () { return []; });
  }

  function getAlerts() {
    return fetch(AM_BASE + "/api/v2/alerts?active=true&silenced=false&inhibited=false")
      .then(function (r) { return r.json(); })
      .catch(function () { return []; });
  }

  // ---------- FLEET HEALTH ----------

  var healthEl = document.getElementById("health-bars");

  function barColor(pct) {
    if (pct >= 85) return "red";
    if (pct >= 70) return "yellow";
    return "green";
  }

  function renderHealth(cpu, mem, disk) {
    var html = "";
    HOSTS.forEach(function (h) {
      var c = cpu[h.instance], m = mem[h.instance], d = disk[h.instance];
      html += '<div class="health-row">';
      html += '<span class="health-host">' + h.name + '</span>';
      html += '<div class="health-metrics">';

      if (c !== undefined && m !== undefined && d !== undefined) {
        html += metricHtml("CPU", c);
        html += metricHtml("MEM", m);
        html += metricHtml("DSK", d);
      } else {
        html += '<span class="health-unavailable">unavailable</span>';
      }

      html += '</div></div>';
    });
    healthEl.innerHTML = html;
  }

  function metricHtml(label, pct) {
    var color = barColor(pct);
    return '<div class="metric">' +
      '<span class="metric-label">' + label + '</span>' +
      '<div class="bar-container"><div class="bar-fill ' + color + '" style="width:' + pct + '%"></div></div>' +
      '<span class="metric-value">' + Math.round(pct) + '%</span>' +
      '</div>';
  }

  function fetchHealth() {
    var cpuQ = 'avg by(instance) (100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100))';
    var memQ = '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100';
    var dskQ = '(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100';

    Promise.all([promQuery(cpuQ), promQuery(memQ), promQuery(dskQ)]).then(function (results) {
      var cpu = {}, mem = {}, disk = {};
      results[0].forEach(function (r) { cpu[r.metric.instance] = parseFloat(r.value[1]); });
      results[1].forEach(function (r) { mem[r.metric.instance] = parseFloat(r.value[1]); });
      results[2].forEach(function (r) { disk[r.metric.instance] = parseFloat(r.value[1]); });
      renderHealth(cpu, mem, disk);
    });
  }

  // ---------- ALERTS ----------

  var alertsEl = document.getElementById("alerts-content");

  function renderAlerts(alerts) {
    if (alerts.length === 0) {
      alertsEl.innerHTML = '<span class="alerts-clear">All clear</span>';
      return;
    }
    var html = '<span class="alerts-firing">' + alerts.length + ' firing</span>';
    alerts.forEach(function (a) {
      var host = a.labels.host || a.labels.instance || "";
      html += '<div class="alert-item"><span class="alert-name">' + a.labels.alertname + '</span>';
      if (host) html += '<span class="alert-host">' + host + '</span>';
      html += '</div>';
    });
    alertsEl.innerHTML = html;
  }

  function fetchAlerts() {
    getAlerts().then(function (alerts) { renderAlerts(alerts); });
  }

  // ---------- UPTIME ----------

  var uptimeStatusEl = document.getElementById("uptime-status");
  var uptimeBarsEl = document.getElementById("uptime-bars");
  var slideoutOpen = false;

  // Build flat list of all services with their probe targets
  var allServices = [];
  SERVICE_DATA.forEach(function (cat) {
    cat.services.forEach(function (svc) {
      allServices.push({ name: svc.name, category: cat.category, probe: svc.probe || null });
    });
  });

  function toggleSlideout() {
    slideoutOpen = !slideoutOpen;
    var el = document.getElementById("uptime-slideout");
    var chev = document.getElementById("chevron");
    if (slideoutOpen) {
      el.classList.add("visible");
      chev.classList.add("open");
    } else {
      el.classList.remove("visible");
      chev.classList.remove("open");
    }
  }

  function uptimeColor(pct, isDown) {
    if (isDown) return "down";
    if (pct === null) return "healthy";
    if (pct < 95) return "degraded";
    return "healthy";
  }

  function renderUptime(probeStatus, probeUptime, activeAlertNames) {
    // Build lookup: probe target -> current status
    var statusMap = {};
    probeStatus.forEach(function (r) {
      var target = r.metric.instance;
      statusMap[target] = parseFloat(r.value[1]);
    });

    // Build lookup: probe target -> 30d uptime
    var uptimeMap = {};
    probeUptime.forEach(function (r) {
      var target = r.metric.instance;
      uptimeMap[target] = parseFloat(r.value[1]) * 100;
    });

    // Count issues
    var issueCount = 0;
    var rowsByCategory = {};

    allServices.forEach(function (svc) {
      var isDown = false;
      var pct = null;

      if (svc.probe && statusMap[svc.probe] !== undefined) {
        var current = statusMap[svc.probe];
        pct = uptimeMap[svc.probe] !== undefined ? uptimeMap[svc.probe] : null;
        if (current === 0) isDown = true;
      }

      // Check if any active alert mentions this service
      var hasAlert = false;
      activeAlertNames.forEach(function (aName) {
        if (svc.name.toLowerCase().indexOf(aName.toLowerCase()) !== -1 ||
            aName.toLowerCase().indexOf(svc.name.toLowerCase()) !== -1) {
          hasAlert = true;
        }
      });

      var hasIssue = isDown || hasAlert || (pct !== null && pct < 95);
      if (hasIssue) issueCount++;

      var color = uptimeColor(pct, isDown);

      if (!rowsByCategory[svc.category]) rowsByCategory[svc.category] = [];
      rowsByCategory[svc.category].push({
        name: svc.name,
        pct: pct,
        color: color,
        hasIssue: hasIssue,
        isDown: isDown
      });
    });

    // Summary line
    if (issueCount === 0) {
      uptimeStatusEl.innerHTML = '<span class="alerts-clear">All services healthy</span>';
    } else {
      uptimeStatusEl.innerHTML = '<span class="alerts-firing">' + issueCount + ' service' + (issueCount > 1 ? 's' : '') + ' degraded</span>';
    }

    // Slideout content
    var html = "";
    SERVICE_DATA.forEach(function (cat) {
      var rows = rowsByCategory[cat.category];
      if (!rows) return;
      html += '<div class="uptime-category">';
      html += '<div class="uptime-category-title">' + cat.category + '</div>';
      rows.forEach(function (r) {
        html += '<div class="uptime-row">';
        html += '<span class="uptime-name' + (r.hasIssue ? ' has-issue' : '') + '">' + r.name + '</span>';
        html += '<span class="uptime-indicator ' + r.color + '"></span>';
        if (r.pct !== null) {
          var barColor = r.color === "down" ? "red" : r.color === "degraded" ? "yellow" : "green";
          html += '<div class="uptime-bar-container"><div class="uptime-bar-fill" style="width:' + r.pct + '%; background:var(--' + barColor + ')"></div></div>';
          html += '<span class="uptime-pct">' + r.pct.toFixed(1) + '%</span>';
        } else {
          html += '<span class="uptime-no-data">—</span>';
        }
        html += '</div>';
      });
      html += '</div>';
    });
    uptimeBarsEl.innerHTML = html;
  }

  function fetchUptime() {
    var statusQ = 'probe_success{job="blackbox-tls"}';
    var uptimeQ = 'avg_over_time(probe_success{job="blackbox-tls"}[30d]) * 100';

    Promise.all([promQuery(statusQ), promQuery(uptimeQ), getAlerts()]).then(function (results) {
      var alertNames = results[2].map(function (a) { return a.labels.alertname; });
      renderUptime(results[0], results[1], alertNames);
    });
  }

  // ---------- SERVICE TILES ----------

  var tilesEl = document.getElementById("tiles-container");

  function renderTiles() {
    var html = "";
    SERVICE_DATA.forEach(function (cat) {
      html += '<div class="tile-category">';
      html += '<div class="tile-category-title">' + cat.category + '</div>';
      html += '<div class="tiles-grid">';
      cat.services.forEach(function (svc) {
        html += '<a class="tile" href="' + svc.href + '">';
        html += '<span class="tile-name">' + svc.name + '</span>';
        html += '<span class="tile-desc">' + svc.desc + '</span>';
        html += '</a>';
      });
      html += '</div></div>';
    });
    tilesEl.innerHTML = html;
  }

  // ---------- INIT ----------

  renderTiles();
  fetchHealth();
  fetchAlerts();
  fetchUptime();

  // Poll every 30s
  setInterval(function () {
    fetchHealth();
    fetchAlerts();
    fetchUptime();
  }, 30000);

})();
