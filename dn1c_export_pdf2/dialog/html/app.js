/* -------------------------------------------------------------------------------
   DN1C Export PDF 2 - Frontend Application Logic
   Provides two-way binding between HTML UI and SketchUp Ruby API
------------------------------------------------------------------------------- */

(function () {
  "use strict";

  // App State
  const state = {
    project_info: {},
    pdf_settings: {},
    scenes: [],
    history: [],
    lastExportedPdf: ""
  };

  // DOM Elements Cache
  const els = {
    tabs: document.querySelectorAll(".tab-btn"),
    tabPanes: document.querySelectorAll(".tab-pane"),
    toast: document.getElementById("toastNotification"),
    sceneCountBadge: document.getElementById("sceneCountBadge"),

    // Header Titles
    headerProjectTitle: document.getElementById("headerProjectTitle"),
    headerProjectSubtitle: document.getElementById("headerProjectSubtitle"),

    // Tab 1 Inputs
    inputRoomName: document.getElementById("inputRoomName"),
    inputFurnitureName: document.getElementById("inputFurnitureName"),
    inputCustomer: document.getElementById("inputCustomer"),
    inputArticul: document.getElementById("inputArticul"),
    inputPhone: document.getElementById("inputPhone"),
    inputEmail: document.getElementById("inputEmail"),
    inputAddress: document.getElementById("inputAddress"),
    inputVersion: document.getElementById("inputVersion"),
    inputRevision: document.getElementById("inputRevision"),
    inputStatus: document.getElementById("inputStatus"),

    // Tab 2 Inputs (Task Brief)
    inputTaskDescription: document.getElementById("inputTaskDescription"),
    inputTaskDimensions: document.getElementById("inputTaskDimensions"),
    inputTaskWishes: document.getElementById("inputTaskWishes"),

    // Tab 3 Inputs (Specs)
    inputMaterials: document.getElementById("inputMaterials"),
    inputAppliances: document.getElementById("inputAppliances"),
    inputLighting: document.getElementById("inputLighting"),
    inputNotes: document.getElementById("inputNotes"),

    // Tab 2 Elements
    scenesTableBody: document.getElementById("scenesTableBody"),
    btnSelectAllScenes: document.getElementById("btnSelectAllScenes"),
    btnDeselectAllScenes: document.getElementById("btnDeselectAllScenes"),
    btnAutoMapScenes: document.getElementById("btnAutoMapScenes"),

    // Tab 3 Inputs
    selectExportEngine: document.getElementById("selectExportEngine"),
    engineHintText: document.getElementById("engineHintText"),
    layoutRenderModeGroup: document.getElementById("layoutRenderModeGroup"),
    selectLayoutRenderMode: document.getElementById("selectLayoutRenderMode"),
    layoutSaveFileGroup: document.getElementById("layoutSaveFileGroup"),
    chkSaveLayoutFile: document.getElementById("chkSaveLayoutFile"),
    selectPageSize: document.getElementById("selectPageSize"),
    selectPageLayout: document.getElementById("selectPageLayout"),
    selectQuality: document.getElementById("selectQuality"),
    selectStamp: document.getElementById("selectStamp"),
    customStampGroup: document.getElementById("customStampGroup"),
    inputCustomStamp: document.getElementById("inputCustomStamp"),
    inputPrimaryColor: document.getElementById("inputPrimaryColor"),
    primaryColorHex: document.getElementById("primaryColorHex"),
    inputStampColor: document.getElementById("inputStampColor"),
    stampColorHex: document.getElementById("stampColorHex"),
    chkAutoOpen: document.getElementById("chkAutoOpen"),
    chkSaveBackup: document.getElementById("chkSaveBackup"),
    chkAntialias: document.getElementById("chkAntialias"),

    // Tab 4 Elements
    historyTableBody: document.getElementById("historyTableBody"),
    btnAddHistoryEntry: document.getElementById("btnAddHistoryEntry"),

    // Global Actions
    btnSaveData: document.getElementById("btnSaveData"),
    btnStartExport: document.getElementById("btnStartExport"),
    btnImportYaml: document.getElementById("btnImportYaml"),
    btnExportYaml: document.getElementById("btnExportYaml"),

    // Overlays
    progressOverlay: document.getElementById("progressOverlay"),
    progressBarFill: document.getElementById("progressBarFill"),
    progressPercent: document.getElementById("progressPercent"),
    progressMessage: document.getElementById("progressMessage"),

    // Success Modal
    successModal: document.getElementById("successModal"),
    successPdfPath: document.getElementById("successPdfPath"),
    btnOpenPdfFolder: document.getElementById("btnOpenPdfFolder"),
    btnCloseSuccessModal: document.getElementById("btnCloseSuccessModal")
  };

  // SketchUp Bridge Helper
  function callRuby(action, param) {
    if (window.sketchup && typeof window.sketchup[action] === "function") {
      if (param !== undefined) {
        window.sketchup[action](param);
      } else {
        window.sketchup[action]();
      }
    } else {
      console.log(`[Mock Ruby Call] action=${action}, param=`, param);
    }
  }

  // Navigation Tabs Switching
  function setupTabs() {
    els.tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        els.tabs.forEach((t) => t.classList.remove("active"));
        els.tabPanes.forEach((p) => p.classList.remove("active"));

        tab.classList.add("active");
        const targetPane = document.getElementById(tab.dataset.tab);
        if (targetPane) {
          targetPane.classList.add("active");
        }
      });
    });
  }

  // Toast Notifications
  let toastTimer = null;
  function showNotification(msg, type = "success") {
    clearTimeout(toastTimer);
    els.toast.textContent = msg;
    els.toast.className = `toast ${type}`;
    els.toast.classList.remove("hidden");

    toastTimer = setTimeout(() => {
      els.toast.classList.add("hidden");
    }, 3500);
  }

  // Populate UI from State
  function renderUI() {
    const info = state.project_info || {};
    const settings = state.pdf_settings || {};

    // Project Info
    els.inputRoomName.value = info.room_name || "";
    els.inputFurnitureName.value = info.furniture_name || "";
    els.inputCustomer.value = info.name_customer || "";
    els.inputArticul.value = info.articul || "";
    els.inputPhone.value = info.phone || "";
    els.inputEmail.value = info.email || "";
    els.inputAddress.value = info.address || "";
    els.inputVersion.value = info.version || 1;
    els.inputRevision.value = info.revision || 1;
    els.inputStatus.value = info.status || "В РАБОТЕ";

    // Task Brief
    if (els.inputTaskDescription) els.inputTaskDescription.value = info.task_description || "";
    if (els.inputTaskDimensions) els.inputTaskDimensions.value = info.task_dimensions || "";
    if (els.inputTaskWishes) els.inputTaskWishes.value = info.task_wishes || "";

    // Specifications
    els.inputMaterials.value = info.materials || "";
    if (els.inputAppliances) els.inputAppliances.value = info.appliances || "";
    els.inputLighting.value = info.lighting || "";
    els.inputNotes.value = info.notes || "";

    // PDF Settings
    const engine = settings.export_engine || "prawn";
    if (els.selectExportEngine) els.selectExportEngine.value = engine;
    if (els.selectLayoutRenderMode) els.selectLayoutRenderMode.value = settings.layout_render_mode || "raster";
    if (els.chkSaveLayoutFile) els.chkSaveLayoutFile.checked = settings.save_layout_file !== false;
    updateEngineUI();

    els.selectPageSize.value = settings.page_size || "A4";
    els.selectPageLayout.value = settings.page_layout || "landscape";
    els.selectQuality.value = (settings.scale_factor || 2.0).toString();
    els.selectStamp.value = settings.stamp_type || "draft";
    els.inputCustomStamp.value = settings.stamp_custom || "НЕ УТВЕРЖДЕН";
    els.customStampGroup.style.display = settings.stamp_type === "custom" ? "flex" : "none";

    const pColor = settings.primary_color ? `#${settings.primary_color}` : "#005EB0";
    els.inputPrimaryColor.value = pColor;
    els.primaryColorHex.textContent = pColor;

    const sColor = settings.stamp_color ? `#${settings.stamp_color}` : "#D32F2F";
    els.inputStampColor.value = sColor;
    els.stampColorHex.textContent = sColor;

    els.chkAutoOpen.checked = settings.auto_open_pdf !== false;
    els.chkSaveBackup.checked = settings.save_skp_backup !== false;
    els.chkAntialias.checked = settings.antialias !== false;

    updateHeaderTitles();
    renderScenesTable();
    renderHistoryTable();
  }

  // Update LayOut / Prawn Engine UI State
  function updateEngineUI() {
    const isLayout = els.selectExportEngine && els.selectExportEngine.value === "layout";
    if (els.layoutRenderModeGroup) els.layoutRenderModeGroup.style.display = isLayout ? "flex" : "none";
    if (els.layoutSaveFileGroup) els.layoutSaveFileGroup.style.display = isLayout ? "flex" : "none";

    if (els.engineHintText) {
      if (isLayout) {
        els.engineHintText.textContent = "LayOut API создает полноценный документ LayOut со страницами и видовыми экранами SketchUp и экспортирует его в PDF.";
      } else {
        els.engineHintText.textContent = "Prawn генерирует PDF напрямую, используя векторные примитивы и высококачественные растровые рендеры сцен.";
      }
    }
  }

  // Update Header Title & Subtitle
  function updateHeaderTitles() {
    const room = (els.inputRoomName ? els.inputRoomName.value : "").trim();
    const furniture = (els.inputFurnitureName ? els.inputFurnitureName.value : "").trim();
    const parts = [room, furniture].filter(Boolean);
    const pTitle = parts.length ? parts.join(" — ") : "Новый проект";

    const customer = (els.inputCustomer ? els.inputCustomer.value : "").trim();
    const address = (els.inputAddress ? els.inputAddress.value : "").trim();
    const subParts = [customer, address].filter(Boolean);
    const subText = subParts.length ? subParts.join(" — ") : "Заказчик — Адрес объекта";

    if (els.headerProjectTitle) els.headerProjectTitle.textContent = pTitle;
    if (els.headerProjectSubtitle) els.headerProjectSubtitle.textContent = subText;
  }

  // Render Scenes Table
  function renderScenesTable() {
    els.scenesTableBody.innerHTML = "";
    const scenes = state.scenes || [];
    els.sceneCountBadge.textContent = scenes.length;

    scenes.forEach((scene, index) => {
      const tr = document.createElement("tr");

      // Checkbox Enabled
      const tdCheck = document.createElement("td");
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = scene.enabled !== false;
      chk.addEventListener("change", (e) => {
        scene.enabled = e.target.checked;
      });
      tdCheck.appendChild(chk);

      // Index
      const tdNum = document.createElement("td");
      tdNum.textContent = index + 1;
      tdNum.style.color = "var(--text-dim)";

      // Scene Name
      const tdName = document.createElement("td");
      tdName.textContent = scene.name;
      tdName.style.fontWeight = "600";

      // Page Type Select
      const tdType = document.createElement("td");
      const selType = document.createElement("select");
      selType.className = "table-select";
      const types = [
        { value: "cover", label: "Титульный лист (Cover)" },
        { value: "description", label: "Описание проекта (Description)" },
        { value: "explain", label: "Содержание и ведомость (Explain)" },
        { value: "visual", label: "Визуализация (Visual)" },
        { value: "general", label: "Общий вид (General)" }
      ];
      types.forEach((t) => {
        const opt = document.createElement("option");
        opt.value = t.value;
        opt.textContent = t.label;
        if (scene.page_type === t.value) opt.selected = true;
        selType.appendChild(opt);
      });
      selType.addEventListener("change", (e) => {
        scene.page_type = e.target.value;
      });
      tdType.appendChild(selType);

      // Description Input
      const tdDesc = document.createElement("td");
      const inputDesc = document.createElement("input");
      inputDesc.type = "text";
      inputDesc.className = "table-input";
      inputDesc.value = scene.description || "";
      inputDesc.placeholder = "Примечание к виду...";
      inputDesc.addEventListener("input", (e) => {
        scene.description = e.target.value;
      });
      tdDesc.appendChild(inputDesc);

      // Order Up / Down Buttons
      const tdOrder = document.createElement("td");
      const btnGroup = document.createElement("div");
      btnGroup.className = "order-btn-group";

      const btnUp = document.createElement("button");
      btnUp.className = "btn-icon";
      btnUp.textContent = "▲";
      btnUp.title = "Переместить выше";
      btnUp.disabled = index === 0;
      btnUp.addEventListener("click", () => moveScene(index, -1));

      const btnDown = document.createElement("button");
      btnDown.className = "btn-icon";
      btnDown.textContent = "▼";
      btnDown.title = "Переместить ниже";
      btnDown.disabled = index === scenes.length - 1;
      btnDown.addEventListener("click", () => moveScene(index, 1));

      btnGroup.appendChild(btnUp);
      btnGroup.appendChild(btnDown);
      tdOrder.appendChild(btnGroup);

      tr.appendChild(tdCheck);
      tr.appendChild(tdNum);
      tr.appendChild(tdName);
      tr.appendChild(tdType);
      tr.appendChild(tdDesc);
      tr.appendChild(tdOrder);

      els.scenesTableBody.appendChild(tr);
    });
  }

  function moveScene(index, direction) {
    const targetIdx = index + direction;
    if (targetIdx < 0 || targetIdx >= state.scenes.length) return;

    const temp = state.scenes[index];
    state.scenes[index] = state.scenes[targetIdx];
    state.scenes[targetIdx] = temp;

    // Update order indices
    state.scenes.forEach((s, idx) => (s.order = idx));
    renderScenesTable();
  }

  // Render History Table
  function renderHistoryTable() {
    els.historyTableBody.innerHTML = "";
    const history = state.history || [];

    history.forEach((item, index) => {
      const tr = document.createElement("tr");

      const tdDate = document.createElement("td");
      const inputDate = document.createElement("input");
      inputDate.type = "text";
      inputDate.className = "table-input";
      inputDate.value = item.date || "";
      inputDate.addEventListener("input", (e) => {
        item.date = e.target.value;
      });
      tdDate.appendChild(inputDate);

      const tdDesc = document.createElement("td");
      const inputDesc = document.createElement("input");
      inputDesc.type = "text";
      inputDesc.className = "table-input";
      inputDesc.value = item.description || "";
      inputDesc.placeholder = "Описание правок...";
      inputDesc.addEventListener("input", (e) => {
        item.description = e.target.value;
      });
      tdDesc.appendChild(inputDesc);

      const tdDelete = document.createElement("td");
      const btnDel = document.createElement("button");
      btnDel.className = "btn-icon btn-delete";
      btnDel.textContent = "✕";
      btnDel.title = "Удалить запись";
      btnDel.addEventListener("click", () => {
        state.history.splice(index, 1);
        renderHistoryTable();
      });
      tdDelete.appendChild(btnDel);

      tr.appendChild(tdDate);
      tr.appendChild(tdDesc);
      tr.appendChild(tdDelete);

      els.historyTableBody.appendChild(tr);
    });
  }

  // Collect Current Form Data into State
  function collectFormData() {
    const room = (els.inputRoomName ? els.inputRoomName.value : "").trim();
    const furniture = (els.inputFurnitureName ? els.inputFurnitureName.value : "").trim();
    const computedTitle = [room, furniture].filter(Boolean).join(" — ") || "Проект";

    state.project_info = {
      room_name: room,
      furniture_name: furniture,
      name_project: computedTitle,
      name_customer: (els.inputCustomer ? els.inputCustomer.value : "").trim(),
      articul: (els.inputArticul ? els.inputArticul.value : "").trim(),
      phone: (els.inputPhone ? els.inputPhone.value : "").trim(),
      email: (els.inputEmail ? els.inputEmail.value : "").trim(),
      address: (els.inputAddress ? els.inputAddress.value : "").trim(),
      version: parseInt(els.inputVersion ? els.inputVersion.value : 1, 10) || 1,
      revision: parseInt(els.inputRevision ? els.inputRevision.value : 1, 10) || 1,
      status:           els.inputStatus ? els.inputStatus.value : "В РАБОТЕ",
      task_description: (els.inputTaskDescription ? els.inputTaskDescription.value : "").trim(),
      task_dimensions:  (els.inputTaskDimensions ? els.inputTaskDimensions.value : "").trim(),
      task_wishes:      (els.inputTaskWishes ? els.inputTaskWishes.value : "").trim(),
      materials:        (els.inputMaterials ? els.inputMaterials.value : "").trim(),
      appliances:       (els.inputAppliances ? els.inputAppliances.value : "").trim(),
      lighting:         (els.inputLighting ? els.inputLighting.value : "").trim(),
      notes:            (els.inputNotes ? els.inputNotes.value : "").trim()
    };

    state.pdf_settings = {
      export_engine: els.selectExportEngine ? els.selectExportEngine.value : "prawn",
      layout_render_mode: els.selectLayoutRenderMode ? els.selectLayoutRenderMode.value : "raster",
      save_layout_file: els.chkSaveLayoutFile ? els.chkSaveLayoutFile.checked : true,
      page_size: els.selectPageSize.value,
      page_layout: els.selectPageLayout.value,
      scale_factor: parseFloat(els.selectQuality.value) || 2.0,
      stamp_type: els.selectStamp.value,
      stamp_custom: els.inputCustomStamp.value.trim(),
      primary_color: els.inputPrimaryColor.value.replace("#", ""),
      stamp_color: els.inputStampColor.value.replace("#", ""),
      auto_open_pdf: els.chkAutoOpen.checked,
      save_skp_backup: els.chkSaveBackup.checked,
      antialias: els.chkAntialias.checked
    };

    return state;
  }

  // Event Listeners Initialization
  function setupEventListeners() {
    // Dynamic update of header titles
    els.inputRoomName.addEventListener("input", updateHeaderTitles);
    els.inputFurnitureName.addEventListener("input", updateHeaderTitles);
    els.inputCustomer.addEventListener("input", updateHeaderTitles);
    els.inputAddress.addEventListener("input", updateHeaderTitles);

    // Export engine select change
    if (els.selectExportEngine) {
      els.selectExportEngine.addEventListener("change", updateEngineUI);
    }

    // Stamp select change
    els.selectStamp.addEventListener("change", (e) => {
      els.customStampGroup.style.display = e.target.value === "custom" ? "flex" : "none";
    });

    // Color pickers hex display
    els.inputPrimaryColor.addEventListener("input", (e) => {
      els.primaryColorHex.textContent = e.target.value;
    });
    els.inputStampColor.addEventListener("input", (e) => {
      els.stampColorHex.textContent = e.target.value;
    });

    // Quick Scene Selection
    els.btnSelectAllScenes.addEventListener("click", () => {
      state.scenes.forEach((s) => (s.enabled = true));
      renderScenesTable();
    });

    els.btnDeselectAllScenes.addEventListener("click", () => {
      state.scenes.forEach((s) => (s.enabled = false));
      renderScenesTable();
    });

    els.btnAutoMapScenes.addEventListener("click", () => {
      state.scenes.forEach((s) => {
        const lower = s.name.toLowerCase();
        if (lower.includes("обложк") || lower.includes("cover") || lower.includes("титул")) {
          s.page_type = "cover";
        } else if (lower.includes("пояснен") || lower.includes("содержан") || lower.includes("оглавлен") || lower.includes("explain") || lower.includes("toc")) {
          s.page_type = "explain";
        } else if (lower.includes("описан") || lower.includes("специфик") || lower.includes("материал") || lower.includes("фурнитур") || lower.includes("электрик") || lower.includes("подсветк") || lower.includes("description") || lower.includes("spec")) {
          s.page_type = "description";
        } else if (lower.includes("визуал") || lower.includes("visual") || lower.includes("рендер") || lower.includes("render")) {
          s.page_type = "visual";
        } else {
          s.page_type = "general";
        }
      });
      renderScenesTable();
      showNotification("Шаблоны страниц автоматически сопоставлены", "success");
    });

    // Add History Entry
    els.btnAddHistoryEntry.addEventListener("click", () => {
      const today = new Date().toISOString().slice(0, 10).replace(/-/g, ".");
      state.history.push({
        date: today,
        description: "Новые правки и спецификации"
      });
      renderHistoryTable();
    });

    // Save Data
    els.btnSaveData.addEventListener("click", () => {
      const data = collectFormData();
      callRuby("saveData", JSON.stringify(data));
    });

    // Start Export
    els.btnStartExport.addEventListener("click", () => {
      const data = collectFormData();
      const enabledScenes = (data.scenes || []).filter((s) => s.enabled && s.page_type !== "skip");
      if (enabledScenes.length === 0) {
        showNotification("Выберите хотя бы одну сцену для экспорта!", "error");
        return;
      }

      els.progressBarFill.style.width = "0%";
      els.progressPercent.textContent = "0%";
      els.progressMessage.textContent = "Инициализация...";
      els.progressOverlay.classList.remove("hidden");

      callRuby("startExport", JSON.stringify(data));
    });

    // Import / Export YAML
    els.btnImportYaml.addEventListener("click", () => {
      callRuby("importYaml");
    });

    els.btnExportYaml.addEventListener("click", () => {
      const data = collectFormData();
      callRuby("exportYaml", JSON.stringify(data));
    });

    // Success Modal
    els.btnOpenPdfFolder.addEventListener("click", () => {
      if (state.lastExportedPdf) {
        callRuby("openFolder", state.lastExportedPdf);
      }
    });

    els.btnCloseSuccessModal.addEventListener("click", () => {
      els.successModal.classList.add("hidden");
    });
  }

  // Public API exposed on window.app for Ruby calls
  window.app = {
    loadData: function (data) {
      if (!data) return;
      Object.assign(state, data);
      renderUI();
    },

    showNotification: showNotification,

    updateProgress: function (percent, message) {
      els.progressBarFill.style.width = `${percent}%`;
      els.progressPercent.textContent = `${percent}%`;
      if (message) {
        els.progressMessage.textContent = message;
      }
    },

    onExportSuccess: function (pdfPath) {
      els.progressOverlay.classList.add("hidden");
      state.lastExportedPdf = pdfPath;
      els.successPdfPath.textContent = pdfPath;
      els.successModal.classList.remove("hidden");

      // Auto increment revision locally
      const revInput = els.inputRevision;
      revInput.value = (parseInt(revInput.value, 10) || 1) + 1;
    },

    onExportError: function (errorMsg) {
      els.progressOverlay.classList.add("hidden");
      showNotification(`Ошибка экспорта: ${errorMsg}`, "error");
    }
  };

  // Initialization
  document.addEventListener("DOMContentLoaded", () => {
    setupTabs();
    setupEventListeners();

    // Request initial data from SketchUp
    callRuby("getData");
  });
})();
