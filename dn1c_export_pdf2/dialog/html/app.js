/* -------------------------------------------------------------------------------
   DN1C Export PDF 2 - Frontend Application Logic
   Provides two-way binding between HTML UI and SketchUp Ruby API,
   plus Interactive WYSIWYG Page Layout Editor (Drag & Drop Block Positioning)
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

  // Default block layouts template definitions
  const DEFAULT_LAYOUTS = {
    cover: {
      name: "Титульный лист (Cover)",
      blocks: [
        { id: "cover_accent_bar", label: "Верхняя акцентная полоса", icon: "➖", x: 0.0, y: 0.0, w: 100.0, h: 1.5, visible: true },
        { id: "cover_articul", label: "Артикул / Код проекта", icon: "🏷️", x: 65.0, y: 2.5, w: 35.0, h: 4.0, visible: true, align: "right" },
        { id: "cover_title", label: "Главный заголовок проекта", icon: "🔤", x: 0.0, y: 3.5, w: 65.0, h: 8.0, visible: true, align: "left" },
        { id: "cover_subtitle", label: "Заказчик и адрес объекта", icon: "📍", x: 0.0, y: 11.5, w: 100.0, h: 5.0, visible: true, align: "left" },
        { id: "cover_divider", label: "Разделительная линия", icon: "➖", x: 0.0, y: 16.5, w: 100.0, h: 0.5, visible: true },
        { id: "cover_hero_image", label: "Главный рендер / Hero Image", icon: "🖼️", x: 0.0, y: 19.0, w: 56.0, h: 76.0, visible: true, is_image: true },
        { id: "cover_project_card", label: "Карточка реквизитов проекта", icon: "📋", x: 59.0, y: 19.0, w: 41.0, h: 46.0, visible: true },
        { id: "cover_history_card", label: "История изменений и ревизий", icon: "📜", x: 59.0, y: 67.0, w: 41.0, h: 28.0, visible: true },
        { id: "footer", label: "Нижний колонтитул (Footer)", icon: "📑", x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
      ]
    },
    description: {
      name: "Описание и спецификации (Description)",
      blocks: [
        { id: "desc_header", label: "Верхний колонтитул страницы", icon: "🔝", x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
        { id: "desc_materials", label: "Материалы и фурнитура", icon: "🛠️", x: 0.0, y: 9.0, w: 52.0, h: 20.0, visible: true },
        { id: "desc_appliances", label: "Техника и оборудование", icon: "🔌", x: 0.0, y: 31.0, w: 52.0, h: 20.0, visible: true },
        { id: "desc_lighting", label: "Подсветка и электрика", icon: "💡", x: 0.0, y: 53.0, w: 52.0, h: 20.0, visible: true },
        { id: "desc_notes", label: "Пояснительная записка", icon: "📝", x: 0.0, y: 75.0, w: 52.0, h: 20.0, visible: true },
        { id: "desc_image", label: "Видовой экран / 3D рендер", icon: "🖼️", x: 55.0, y: 9.0, w: 45.0, h: 86.0, visible: true, is_image: true },
        { id: "footer", label: "Нижний колонтитул (Footer)", icon: "📑", x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
      ]
    },
    explain: {
      name: "Содержание и ведомость (Explain)",
      blocks: [
        { id: "explain_header", label: "Верхний колонтитул страницы", icon: "🔝", x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
        { id: "explain_toc", label: "Содержание проекта (TOC)", icon: "📑", x: 0.0, y: 9.0, w: 48.0, h: 86.0, visible: true },
        { id: "explain_specs", label: "Спецификации и материалы", icon: "📋", x: 52.0, y: 9.0, w: 48.0, h: 35.0, visible: true },
        { id: "explain_image", label: "Превью рендер модели", icon: "🖼️", x: 52.0, y: 47.0, w: 48.0, h: 48.0, visible: true, is_image: true },
        { id: "footer", label: "Нижний колонтитул (Footer)", icon: "📑", x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
      ]
    },
    general: {
      name: "Общий вид (General)",
      blocks: [
        { id: "general_header", label: "Верхний колонтитул страницы", icon: "🔝", x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
        { id: "general_image", label: "Чертеж / Видовой экран", icon: "🖼️", x: 0.0, y: 9.0, w: 100.0, h: 73.0, visible: true, is_image: true },
        { id: "general_note", label: "Примечание к виду", icon: "💬", x: 0.0, y: 84.0, w: 100.0, h: 11.0, visible: true },
        { id: "footer", label: "Нижний колонтитул (Footer)", icon: "📑", x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
      ]
    },
    visual: {
      name: "Визуализация (Visual)",
      blocks: [
        { id: "visual_header", label: "Баннер заголовка визуализации", icon: "🔝", x: 0.0, y: 0.0, w: 100.0, h: 6.0, visible: true },
        { id: "visual_image", label: "Полноэкранный рендер сцены", icon: "🖼️", x: 0.0, y: 7.0, w: 100.0, h: 88.0, visible: true, is_image: true },
        { id: "footer", label: "Нижний колонтитул (Footer)", icon: "📑", x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
      ]
    }
  };

  // Layout Editor Internal State
  const layoutState = {
    currentTemplate: "cover",
    selectedBlockId: null,
    snapEnabled: true,
    snapGridPct: 2.0, // 2% snap grid
    guidesEnabled: true,
    zoomLevel: 1.0,
    drag: {
      active: false,
      type: null, // 'move' | 'resize'
      handle: null,
      blockId: null,
      startMouseX: 0,
      startMouseY: 0,
      startBox: null,
      containerRect: null
    }
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
    headerProjectArticul: document.getElementById("headerProjectArticul"),

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

    // Layout Editor Elements
    selectLayoutTemplate: document.getElementById("selectLayoutTemplate"),
    layoutPageInfoBadge: document.getElementById("layoutPageInfoBadge"),
    btnToggleSnap: document.getElementById("btnToggleSnap"),
    snapStatusText: document.getElementById("snapStatusText"),
    btnToggleGuides: document.getElementById("btnToggleGuides"),
    guidesStatusText: document.getElementById("guidesStatusText"),
    btnZoomOut: document.getElementById("btnZoomOut"),
    zoomLevelText: document.getElementById("zoomLevelText"),
    btnZoomIn: document.getElementById("btnZoomIn"),
    btnZoomFit: document.getElementById("btnZoomFit"),
    btnResetLayout: document.getElementById("btnResetLayout"),
    layoutCanvasContainer: document.getElementById("layoutCanvasContainer"),
    layoutPageSheet: document.getElementById("layoutPageSheet"),
    sheetGridOverlay: document.getElementById("sheetGridOverlay"),
    layoutBlocksLayer: document.getElementById("layoutBlocksLayer"),
    inspectorBlocksList: document.getElementById("inspectorBlocksList"),
    selectedBlockCard: document.getElementById("selectedBlockCard"),
    inspectorSelectedBlockTitle: document.getElementById("inspectorSelectedBlockTitle"),
    inspectorEmptyState: document.getElementById("inspectorEmptyState"),
    inspectorPropertiesForm: document.getElementById("inspectorPropertiesForm"),
    btnAlignLeft: document.getElementById("btnAlignLeft"),
    btnAlignCenterH: document.getElementById("btnAlignCenterH"),
    btnAlignRight: document.getElementById("btnAlignRight"),
    btnAlignTop: document.getElementById("btnAlignTop"),
    btnAlignCenterV: document.getElementById("btnAlignCenterV"),
    btnAlignBottom: document.getElementById("btnAlignBottom"),
    btnAlignFullWidth: document.getElementById("btnAlignFullWidth"),
    inputBlockX: document.getElementById("inputBlockX"),
    inputBlockY: document.getElementById("inputBlockY"),
    inputBlockW: document.getElementById("inputBlockW"),
    inputBlockH: document.getElementById("inputBlockH"),
    blockTypographyGroup: document.getElementById("blockTypographyGroup"),
    btnTextAlignLeft: document.getElementById("btnTextAlignLeft"),
    btnTextAlignCenter: document.getElementById("btnTextAlignCenter"),
    btnTextAlignRight: document.getElementById("btnTextAlignRight"),
    chkBlockVisible: document.getElementById("chkBlockVisible"),

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
    btnRefreshData: document.getElementById("btnRefreshData"),
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
          if (tab.dataset.tab === "tab-layout") {
            renderLayoutCanvas();
          }
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

  // -----------------------------------------------------------------------------
  // Layout Editor Core Engine
  // -----------------------------------------------------------------------------

  function ensureCustomLayouts() {
    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};

    Object.keys(DEFAULT_LAYOUTS).forEach((tplKey) => {
      if (!state.pdf_settings.custom_layouts[tplKey]) {
        state.pdf_settings.custom_layouts[tplKey] = {};
      }
      const tplDef = DEFAULT_LAYOUTS[tplKey];
      tplDef.blocks.forEach((defBlk) => {
        if (!state.pdf_settings.custom_layouts[tplKey][defBlk.id]) {
          state.pdf_settings.custom_layouts[tplKey][defBlk.id] = {
            x: defBlk.x,
            y: defBlk.y,
            w: defBlk.w,
            h: defBlk.h,
            visible: defBlk.visible !== false,
            align: defBlk.align || "left"
          };
        }
      });
    });
  }

  function getActiveLayoutBlocks() {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate;
    const tplDef = DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS.cover;
    const customTpl = state.pdf_settings.custom_layouts[tplKey] || {};

    return tplDef.blocks.map((defBlk) => {
      const custom = customTpl[defBlk.id] || {};
      return {
        id: defBlk.id,
        label: defBlk.label,
        icon: defBlk.icon,
        is_image: !!defBlk.is_image,
        x: custom.x !== undefined ? parseFloat(custom.x) : defBlk.x,
        y: custom.y !== undefined ? parseFloat(custom.y) : defBlk.y,
        w: custom.w !== undefined ? parseFloat(custom.w) : defBlk.w,
        h: custom.h !== undefined ? parseFloat(custom.h) : defBlk.h,
        visible: custom.visible !== undefined ? custom.visible : (defBlk.visible !== false),
        align: custom.align || defBlk.align || "left"
      };
    });
  }

  function getBlockData(blockId) {
    const blocks = getActiveLayoutBlocks();
    return blocks.find((b) => b.id === blockId) || null;
  }

  function updateBlockCoordinates(blockId, updates) {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate;
    if (!state.pdf_settings.custom_layouts[tplKey]) {
      state.pdf_settings.custom_layouts[tplKey] = {};
    }
    if (!state.pdf_settings.custom_layouts[tplKey][blockId]) {
      const defBlk = (DEFAULT_LAYOUTS[tplKey]?.blocks || []).find((b) => b.id === blockId) || {};
      state.pdf_settings.custom_layouts[tplKey][blockId] = {
        x: defBlk.x || 0,
        y: defBlk.y || 0,
        w: defBlk.w || 50,
        h: defBlk.h || 20,
        visible: defBlk.visible !== false,
        align: defBlk.align || "left"
      };
    }

    Object.assign(state.pdf_settings.custom_layouts[tplKey][blockId], updates);
  }

  // Generate live content preview for a block on the virtual sheet
  function generateBlockPreviewHtml(blk) {
    const info = state.project_info || {};
    const room = (info.room_name || "").trim() || "Кухня-гостиная";
    const furn = (info.furniture_name || "").trim() || "Кухонный гарнитур";
    const fullTitle = [room, furn].filter(Boolean).join(" — ");
    const customer = (info.name_customer || "").trim() || "Заказчик: Иванов И.И.";
    const address = (info.address || "").trim() || "г. Москва, ул. Примерная, д. 10";
    const articul = (info.articul || "").trim() || "PRJ-2026-001";

    if (blk.is_image) {
      return `
        <div class="block-image-placeholder">
          <span>🖼️</span>
          <div>${blk.label}</div>
        </div>
      `;
    }

    switch (blk.id) {
      case "cover_accent_bar":
        return `<div style="height: 100%; background: #005EB0; border-radius: 2px;"></div>`;
      case "cover_articul":
        return `<div style="font-weight: 700; color: #005EB0; text-align: ${blk.align};">АРТ: ${articul}</div>`;
      case "cover_title":
        return `<div style="font-size: 11.5px; font-weight: 800; color: #005EB0; text-align: ${blk.align};">${fullTitle}</div>`;
      case "cover_subtitle":
        return `<div style="font-size: 9.5px; color: #64748B; text-align: ${blk.align};">${customer} • ${address}</div>`;
      case "cover_divider":
        return `<div style="border-top: 1px solid #CBD5E1; margin-top: 2px;"></div>`;
      case "cover_project_card":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px; margin-bottom: 2px;">📋 ДАННЫЕ ПРОЕКТА</div>
          <div style="font-size: 8.5px; color: #475569; line-height: 1.2;">
            <div><b>Объект:</b> ${room}</div>
            <div><b>Заказчик:</b> ${info.name_customer || "—"}</div>
            <div><b>Статус:</b> ${info.status || "В РАБОТЕ"}</div>
          </div>
        `;
      case "cover_history_card":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px; margin-bottom: 2px;">📜 РЕВИЗИИ</div>
          <div style="font-size: 8.5px; color: #475569;">v${info.version || 1}#r${info.revision || 1} • ${new Date().toLocaleDateString()}</div>
        `;
      case "desc_materials":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">🛠️ МАТЕРИАЛЫ</div>
          <div style="font-size: 8.5px; color: #334155;">${info.materials || "Фасады, корпус, фурнитура..."}</div>
        `;
      case "desc_appliances":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">🔌 ТЕХНИКА</div>
          <div style="font-size: 8.5px; color: #334155;">${info.appliances || "Встраиваемая техника..."}</div>
        `;
      case "desc_lighting":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">💡 ПОДСВЕТКА</div>
          <div style="font-size: 8.5px; color: #334155;">${info.lighting || "LED 3000K, 24V..."}</div>
        `;
      case "desc_notes":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">📝 ПРИМЕЧАНИЯ</div>
          <div style="font-size: 8.5px; color: #334155;">${info.notes || "Технические требования..."}</div>
        `;
      case "desc_header":
      case "explain_header":
      case "general_header":
        return `<div style="font-size: 9.5px; font-weight: 700; color: #005EB0;">${fullTitle} | ${articul}</div>`;
      case "explain_toc":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">📑 СОДЕРЖАНИЕ</div>
          <div style="font-size: 8.5px; color: #475569;">01. Обложка • 02. Визуализации...</div>
        `;
      case "explain_specs":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9px;">📋 СПЕЦИФИКАЦИИ</div>
          <div style="font-size: 8.5px; color: #475569;">${info.notes || "Основные требования проекта"}</div>
        `;
      case "general_note":
        return `
          <div style="font-size: 9px; color: #334155;"><b>Примечание к виду:</b> Габаритные размеры и привязки</div>
        `;
      case "visual_header":
        return `
          <div style="font-weight: 700; color: #005EB0; font-size: 9.5px;">ВИЗУАЛИЗАЦИЯ | ${fullTitle}</div>
        `;
      case "footer":
        return `
          <div style="font-size: 8.5px; color: #94a3b8; display: flex; justify-content: space-between;">
            <span>v${info.version || 1}#r${info.revision || 1}</span>
            <span>Лист 1 из 5</span>
          </div>
        `;
      default:
        return `<div style="font-size: 9px; color: #475569;">${blk.label}</div>`;
    }
  }

  // Render Virtual Sheet & Blocks
  function renderLayoutCanvas() {
    if (!els.layoutBlocksLayer || !els.layoutPageSheet) return;

    // 1. Update Sheet Orientation & Format
    const isPortrait = (els.selectPageLayout ? els.selectPageLayout.value : state.pdf_settings?.page_layout) === "portrait";
    const pageSize = (els.selectPageSize ? els.selectPageSize.value : state.pdf_settings?.page_size) || "A4";

    els.layoutPageSheet.classList.toggle("portrait", isPortrait);
    els.layoutPageSheet.classList.toggle("landscape", !isPortrait);

    if (els.layoutPageInfoBadge) {
      els.layoutPageInfoBadge.textContent = `${pageSize} ${isPortrait ? "Книжная" : "Альбомная"}`;
    }

    // 2. Clear layer
    els.layoutBlocksLayer.innerHTML = "";
    const blocks = getActiveLayoutBlocks();

    // 3. Render blocks on sheet
    blocks.forEach((blk) => {
      const isSelected = blk.id === layoutState.selectedBlockId;

      const blockEl = document.createElement("div");
      blockEl.className = `layout-block-item ${isSelected ? "selected" : ""} ${!blk.visible ? "hidden-block" : ""}`;
      blockEl.id = `layoutBlock_${blk.id}`;
      blockEl.style.left = `${blk.x}%`;
      blockEl.style.top = `${blk.y}%`;
      blockEl.style.width = `${blk.w}%`;
      blockEl.style.height = `${blk.h}%`;

      // Header strip
      const headerStrip = document.createElement("div");
      headerStrip.className = "block-header-strip";
      headerStrip.innerHTML = `<span>${blk.icon} ${blk.label}</span><span>${Math.round(blk.w)}×${Math.round(blk.h)}%</span>`;
      blockEl.appendChild(headerStrip);

      // Body preview
      const bodyPreview = document.createElement("div");
      bodyPreview.className = "block-body-preview";
      bodyPreview.innerHTML = generateBlockPreviewHtml(blk);
      blockEl.appendChild(bodyPreview);

      // If selected, add 8 resize handles
      if (isSelected) {
        const handles = ["nw", "n", "ne", "e", "se", "s", "sw", "w"];
        handles.forEach((dir) => {
          const h = document.createElement("div");
          h.className = `resize-handle handle-${dir}`;
          h.dataset.handle = dir;
          h.addEventListener("mousedown", (e) => onHandleMouseDown(e, blk.id, dir));
          blockEl.appendChild(h);
        });
      }

      // Mouse drag event
      blockEl.addEventListener("mousedown", (e) => {
        if (e.target.classList.contains("resize-handle")) return;
        onBlockMouseDown(e, blk.id);
      });

      els.layoutBlocksLayer.appendChild(blockEl);
    });

    renderInspectorBlocksList();
    updateInspectorForm();
  }

  // Render Inspector List
  function renderInspectorBlocksList() {
    if (!els.inspectorBlocksList) return;
    els.inspectorBlocksList.innerHTML = "";

    const blocks = getActiveLayoutBlocks();
    blocks.forEach((blk) => {
      const row = document.createElement("div");
      row.className = `inspector-block-row ${blk.id === layoutState.selectedBlockId ? "active" : ""}`;

      const label = document.createElement("span");
      label.className = "inspector-block-label";
      label.textContent = `${blk.icon} ${blk.label}`;
      label.addEventListener("click", () => {
        layoutState.selectedBlockId = blk.id;
        renderLayoutCanvas();
      });

      const eyeBtn = document.createElement("button");
      eyeBtn.className = `block-vis-btn ${!blk.visible ? "hidden-eye" : ""}`;
      eyeBtn.innerHTML = blk.visible ? "👁️" : "🕶️";
      eyeBtn.title = blk.visible ? "Скрыть блок" : "Показать блок";
      eyeBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        updateBlockCoordinates(blk.id, { visible: !blk.visible });
        renderLayoutCanvas();
      });

      row.appendChild(label);
      row.appendChild(eyeBtn);
      els.inspectorBlocksList.appendChild(row);
    });
  }

  // Update Inspector Form Fields
  function updateInspectorForm() {
    if (!els.inspectorPropertiesForm || !els.inspectorEmptyState) return;

    const block = layoutState.selectedBlockId ? getBlockData(layoutState.selectedBlockId) : null;

    if (!block) {
      els.inspectorPropertiesForm.classList.add("hidden");
      els.inspectorEmptyState.classList.remove("hidden");
      if (els.inspectorSelectedBlockTitle) {
        els.inspectorSelectedBlockTitle.textContent = "Свойства блока";
      }
      return;
    }

    els.inspectorEmptyState.classList.add("hidden");
    els.inspectorPropertiesForm.classList.remove("hidden");

    if (els.inspectorSelectedBlockTitle) {
      els.inspectorSelectedBlockTitle.textContent = `${block.icon} ${block.label}`;
    }

    els.inputBlockX.value = (Math.round(block.x * 10) / 10).toString();
    els.inputBlockY.value = (Math.round(block.y * 10) / 10).toString();
    els.inputBlockW.value = (Math.round(block.w * 10) / 10).toString();
    els.inputBlockH.value = (Math.round(block.h * 10) / 10).toString();

    els.chkBlockVisible.checked = block.visible !== false;

    // Text Align buttons
    [els.btnTextAlignLeft, els.btnTextAlignCenter, els.btnTextAlignRight].forEach((btn) => {
      if (btn) btn.classList.remove("active");
    });
    const activeAlign = block.align || "left";
    if (activeAlign === "left" && els.btnTextAlignLeft) els.btnTextAlignLeft.classList.add("active");
    if (activeAlign === "center" && els.btnTextAlignCenter) els.btnTextAlignCenter.classList.add("active");
    if (activeAlign === "right" && els.btnTextAlignRight) els.btnTextAlignRight.classList.add("active");
  }

  // -----------------------------------------------------------------------------
  // Mouse Drag & Resize Interactions
  // -----------------------------------------------------------------------------

  function onBlockMouseDown(e, blockId) {
    e.preventDefault();
    layoutState.selectedBlockId = blockId;
    renderLayoutCanvas();

    const block = getBlockData(blockId);
    if (!block) return;

    const containerRect = els.layoutBlocksLayer.getBoundingClientRect();
    layoutState.drag = {
      active: true,
      type: "move",
      handle: null,
      blockId: blockId,
      startMouseX: e.clientX,
      startMouseY: e.clientY,
      startBox: { x: block.x, y: block.y, w: block.w, h: block.h },
      containerRect: containerRect
    };

    const targetEl = document.getElementById(`layoutBlock_${blockId}`);
    if (targetEl) targetEl.classList.add("dragging");
  }

  function onHandleMouseDown(e, blockId, handleDir) {
    e.preventDefault();
    e.stopPropagation();

    layoutState.selectedBlockId = blockId;
    const block = getBlockData(blockId);
    if (!block) return;

    const containerRect = els.layoutBlocksLayer.getBoundingClientRect();
    layoutState.drag = {
      active: true,
      type: "resize",
      handle: handleDir,
      blockId: blockId,
      startMouseX: e.clientX,
      startMouseY: e.clientY,
      startBox: { x: block.x, y: block.y, w: block.w, h: block.h },
      containerRect: containerRect
    };
  }

  function onDocumentMouseMove(e) {
    if (!layoutState.drag.active) return;
    const { type, handle, blockId, startMouseX, startMouseY, startBox, containerRect } = layoutState.drag;

    if (!containerRect || containerRect.width <= 0 || containerRect.height <= 0) return;

    const deltaPctX = ((e.clientX - startMouseX) / containerRect.width) * 100;
    const deltaPctY = ((e.clientY - startMouseY) / containerRect.height) * 100;

    let newX = startBox.x;
    let newY = startBox.y;
    let newW = startBox.w;
    let newH = startBox.h;

    if (type === "move") {
      newX = Math.max(0, Math.min(100 - startBox.w, startBox.x + deltaPctX));
      newY = Math.max(0, Math.min(100 - startBox.h, startBox.y + deltaPctY));

      if (layoutState.snapEnabled) {
        newX = Math.round(newX / layoutState.snapGridPct) * layoutState.snapGridPct;
        newY = Math.round(newY / layoutState.snapGridPct) * layoutState.snapGridPct;
      }
    } else if (type === "resize") {
      const minW = 3.0;
      const minH = 1.5;

      // Handle horizontal sizing
      if (handle.includes("e")) {
        newW = Math.max(minW, Math.min(100 - startBox.x, startBox.w + deltaPctX));
      } else if (handle.includes("w")) {
        const potentialX = startBox.x + deltaPctX;
        const potentialW = startBox.w - deltaPctX;
        if (potentialW >= minW && potentialX >= 0) {
          newX = potentialX;
          newW = potentialW;
        }
      }

      // Handle vertical sizing
      if (handle.includes("s")) {
        newH = Math.max(minH, Math.min(100 - startBox.y, startBox.h + deltaPctY));
      } else if (handle.includes("n")) {
        const potentialY = startBox.y + deltaPctY;
        const potentialH = startBox.h - deltaPctY;
        if (potentialH >= minH && potentialY >= 0) {
          newY = potentialY;
          newH = potentialH;
        }
      }

      if (layoutState.snapEnabled) {
        newX = Math.round(newX / layoutState.snapGridPct) * layoutState.snapGridPct;
        newY = Math.round(newY / layoutState.snapGridPct) * layoutState.snapGridPct;
        newW = Math.round(newW / layoutState.snapGridPct) * layoutState.snapGridPct;
        newH = Math.round(newH / layoutState.snapGridPct) * layoutState.snapGridPct;
      }
    }

    // Clamp values
    newX = Math.max(0, Math.min(100, Math.round(newX * 10) / 10));
    newY = Math.max(0, Math.min(100, Math.round(newY * 10) / 10));
    newW = Math.max(2, Math.min(100 - newX, Math.round(newW * 10) / 10));
    newH = Math.max(1, Math.min(100 - newY, Math.round(newH * 10) / 10));

    // Update in state
    updateBlockCoordinates(blockId, { x: newX, y: newY, w: newW, h: newH });

    // Fast DOM update during drag
    const el = document.getElementById(`layoutBlock_${blockId}`);
    if (el) {
      el.style.left = `${newX}%`;
      el.style.top = `${newY}%`;
      el.style.width = `${newW}%`;
      el.style.height = `${newH}%`;
      const stripSpan = el.querySelector(".block-header-strip span:last-child");
      if (stripSpan) stripSpan.textContent = `${Math.round(newW)}×${Math.round(newH)}%`;
    }

    // Update inspector inputs
    if (els.inputBlockX) els.inputBlockX.value = newX.toString();
    if (els.inputBlockY) els.inputBlockY.value = newY.toString();
    if (els.inputBlockW) els.inputBlockW.value = newW.toString();
    if (els.inputBlockH) els.inputBlockH.value = newH.toString();
  }

  function onDocumentMouseUp() {
    if (layoutState.drag.active) {
      layoutState.drag.active = false;
      const el = document.getElementById(`layoutBlock_${layoutState.drag.blockId}`);
      if (el) el.classList.remove("dragging");
      renderLayoutCanvas();
    }
  }

  // Layout Editor Setup & Listeners
  function setupLayoutEditor() {
    // Template switcher
    if (els.selectLayoutTemplate) {
      els.selectLayoutTemplate.addEventListener("change", (e) => {
        layoutState.currentTemplate = e.target.value;
        layoutState.selectedBlockId = null;
        renderLayoutCanvas();
      });
    }

    // Snap toggle
    if (els.btnToggleSnap) {
      els.btnToggleSnap.addEventListener("click", () => {
        layoutState.snapEnabled = !layoutState.snapEnabled;
        els.btnToggleSnap.classList.toggle("active", layoutState.snapEnabled);
        if (els.snapStatusText) {
          els.snapStatusText.textContent = layoutState.snapEnabled ? "Вкл" : "Выкл";
        }
      });
    }

    // Guides & Grid toggle
    if (els.btnToggleGuides) {
      els.btnToggleGuides.addEventListener("click", () => {
        layoutState.guidesEnabled = !layoutState.guidesEnabled;
        els.btnToggleGuides.classList.toggle("active", layoutState.guidesEnabled);
        if (els.sheetGridOverlay) {
          els.sheetGridOverlay.classList.toggle("hidden", !layoutState.guidesEnabled);
        }
        if (els.guidesStatusText) {
          els.guidesStatusText.textContent = layoutState.guidesEnabled ? "Вкл" : "Выкл";
        }
      });
    }

    // Zoom Controls
    if (els.btnZoomIn) {
      els.btnZoomIn.addEventListener("click", () => {
        layoutState.zoomLevel = Math.min(1.5, Math.round((layoutState.zoomLevel + 0.15) * 100) / 100);
        applyZoom();
      });
    }
    if (els.btnZoomOut) {
      els.btnZoomOut.addEventListener("click", () => {
        layoutState.zoomLevel = Math.max(0.5, Math.round((layoutState.zoomLevel - 0.15) * 100) / 100);
        applyZoom();
      });
    }
    if (els.btnZoomFit) {
      els.btnZoomFit.addEventListener("click", () => {
        layoutState.zoomLevel = 1.0;
        applyZoom();
      });
    }

    function applyZoom() {
      if (els.layoutPageSheet) {
        els.layoutPageSheet.style.transform = `scale(${layoutState.zoomLevel})`;
      }
      if (els.zoomLevelText) {
        els.zoomLevelText.textContent = `${Math.round(layoutState.zoomLevel * 100)}%`;
      }
    }

    // Reset Layout Button
    if (els.btnResetLayout) {
      els.btnResetLayout.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        const defTpl = DEFAULT_LAYOUTS[tplKey];
        if (!defTpl) return;

        if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
        state.pdf_settings.custom_layouts[tplKey] = {};

        defTpl.blocks.forEach((defBlk) => {
          state.pdf_settings.custom_layouts[tplKey][defBlk.id] = {
            x: defBlk.x,
            y: defBlk.y,
            w: defBlk.w,
            h: defBlk.h,
            visible: defBlk.visible !== false,
            align: defBlk.align || "left"
          };
        });

        renderLayoutCanvas();
        showNotification(`Макет страницы «${defTpl.name}» сброшен к исходным позициям`, "success");
      });
    }

    // Numeric inputs for coordinates
    const onCoordInput = () => {
      if (!layoutState.selectedBlockId) return;
      const x = parseFloat(els.inputBlockX.value) || 0;
      const y = parseFloat(els.inputBlockY.value) || 0;
      const w = Math.max(2, parseFloat(els.inputBlockW.value) || 10);
      const h = Math.max(1, parseFloat(els.inputBlockH.value) || 5);

      updateBlockCoordinates(layoutState.selectedBlockId, { x, y, w, h });
      renderLayoutCanvas();
    };

    if (els.inputBlockX) els.inputBlockX.addEventListener("input", onCoordInput);
    if (els.inputBlockY) els.inputBlockY.addEventListener("input", onCoordInput);
    if (els.inputBlockW) els.inputBlockW.addEventListener("input", onCoordInput);
    if (els.inputBlockH) els.inputBlockH.addEventListener("input", onCoordInput);

    // Alignment Buttons
    const applyAlignment = (type) => {
      if (!layoutState.selectedBlockId) return;
      const blk = getBlockData(layoutState.selectedBlockId);
      if (!blk) return;

      let newX = blk.x;
      let newY = blk.y;
      let newW = blk.w;

      switch (type) {
        case "left":
          newX = 0;
          break;
        case "centerH":
          newX = Math.max(0, Math.round((100 - blk.w) / 2));
          break;
        case "right":
          newX = Math.max(0, 100 - blk.w);
          break;
        case "top":
          newY = 0;
          break;
        case "centerV":
          newY = Math.max(0, Math.round((100 - blk.h) / 2));
          break;
        case "bottom":
          newY = Math.max(0, 100 - blk.h);
          break;
        case "fullWidth":
          newX = 0;
          newW = 100;
          break;
      }

      updateBlockCoordinates(blk.id, { x: newX, y: newY, w: newW });
      renderLayoutCanvas();
    };

    if (els.btnAlignLeft) els.btnAlignLeft.addEventListener("click", () => applyAlignment("left"));
    if (els.btnAlignCenterH) els.btnAlignCenterH.addEventListener("click", () => applyAlignment("centerH"));
    if (els.btnAlignRight) els.btnAlignRight.addEventListener("click", () => applyAlignment("right"));
    if (els.btnAlignTop) els.btnAlignTop.addEventListener("click", () => applyAlignment("top"));
    if (els.btnAlignCenterV) els.btnAlignCenterV.addEventListener("click", () => applyAlignment("centerV"));
    if (els.btnAlignBottom) els.btnAlignBottom.addEventListener("click", () => applyAlignment("bottom"));
    if (els.btnAlignFullWidth) els.btnAlignFullWidth.addEventListener("click", () => applyAlignment("fullWidth"));

    // Text Alignment buttons
    const applyTextAlign = (align) => {
      if (!layoutState.selectedBlockId) return;
      updateBlockCoordinates(layoutState.selectedBlockId, { align });
      renderLayoutCanvas();
    };

    if (els.btnTextAlignLeft) els.btnTextAlignLeft.addEventListener("click", () => applyTextAlign("left"));
    if (els.btnTextAlignCenter) els.btnTextAlignCenter.addEventListener("click", () => applyTextAlign("center"));
    if (els.btnTextAlignRight) els.btnTextAlignRight.addEventListener("click", () => applyTextAlign("right"));

    // Visibility Checkbox
    if (els.chkBlockVisible) {
      els.chkBlockVisible.addEventListener("change", (e) => {
        if (!layoutState.selectedBlockId) return;
        updateBlockCoordinates(layoutState.selectedBlockId, { visible: e.target.checked });
        renderLayoutCanvas();
      });
    }

    // Global Document Mouse Handlers
    document.addEventListener("mousemove", onDocumentMouseMove);
    document.addEventListener("mouseup", onDocumentMouseUp);
  }

  // -----------------------------------------------------------------------------
  // Data Population & Form Handling
  // -----------------------------------------------------------------------------

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
    renderLayoutCanvas();
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

    const articul = (els.inputArticul ? els.inputArticul.value : "").trim();

    if (els.headerProjectTitle) els.headerProjectTitle.textContent = pTitle;
    if (els.headerProjectSubtitle) els.headerProjectSubtitle.textContent = subText;
    if (els.headerProjectArticul) {
      els.headerProjectArticul.textContent = articul || "—";
      if (!articul) {
        els.headerProjectArticul.classList.add("empty");
      } else {
        els.headerProjectArticul.classList.remove("empty");
      }
    }

    // Refresh previews in layout canvas
    const layoutTab = document.getElementById("tab-layout");
    if (layoutTab && layoutTab.classList.contains("active")) {
      renderLayoutCanvas();
    }
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

    ensureCustomLayouts();

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
      antialias: els.chkAntialias.checked,
      custom_layouts: state.pdf_settings.custom_layouts
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
    if (els.inputArticul) {
      els.inputArticul.addEventListener("input", updateHeaderTitles);
    }

    // Specifications dynamic preview update
    if (els.inputMaterials) els.inputMaterials.addEventListener("input", updateHeaderTitles);
    if (els.inputAppliances) els.inputAppliances.addEventListener("input", updateHeaderTitles);
    if (els.inputLighting) els.inputLighting.addEventListener("input", updateHeaderTitles);
    if (els.inputNotes) els.inputNotes.addEventListener("input", updateHeaderTitles);

    // Export engine select change
    if (els.selectExportEngine) {
      els.selectExportEngine.addEventListener("change", updateEngineUI);
    }

    // Page orientation / size change updates layout canvas sheet
    if (els.selectPageLayout) {
      els.selectPageLayout.addEventListener("change", renderLayoutCanvas);
    }
    if (els.selectPageSize) {
      els.selectPageSize.addEventListener("change", renderLayoutCanvas);
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

    // Refresh Data (all storages, scenes & YAML)
    if (els.btnRefreshData) {
      els.btnRefreshData.addEventListener("click", () => {
        const data = collectFormData();
        callRuby("refreshData", JSON.stringify(data));
      });
    }

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
      ensureCustomLayouts();
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

    onExportSuccess: function (pdfPath, newRevision) {
      els.progressOverlay.classList.add("hidden");
      state.lastExportedPdf = pdfPath;
      els.successPdfPath.textContent = pdfPath;
      els.successModal.classList.remove("hidden");

      // Auto update revision locally from backend
      if (els.inputRevision) {
        els.inputRevision.value = (newRevision !== undefined && newRevision !== null)
          ? newRevision
          : ((parseInt(els.inputRevision.value, 10) || 1) + 1);
      }
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
    setupLayoutEditor();

    // Request initial data from SketchUp
    callRuby("getData");
  });
})();
