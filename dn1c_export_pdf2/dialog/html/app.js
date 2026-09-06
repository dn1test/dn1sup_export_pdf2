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

  // 7 Standard Layout Zones (matching user diagram)
  // 7 Standard Layout Zones (matching user sketch wireframe)
  const FIXED_SLOT_DEFS = [
    {
      id: "image_4_3",
      label: "КАРТИНКА ПРОЕКТА",
      icon: "🖼️",
      slot_class: "slot-image-4-3",
      x: 0.0, y: 0.0, w: 100.0, h: 100.0,
      is_image: true
    },
    {
      id: "header",
      label: "ЗАГОЛОВОК",
      icon: "🔝",
      slot_class: "slot-header",
      x: 0.0, y: 0.0, w: 100.0, h: 30.0,
      default_lines: ["furniture_name", "place_address", "customer_or_company"],
      default_line_rows: { furniture_name: 1, place_address: 2, customer_or_company: 3, scene_name: 4, scene_description: 5 },
      default_line_font_sizes: { furniture_name: 11, place_address: 10, customer_or_company: 10, scene_name: 11, scene_description: 9 },
      default_line_colors: { furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A", scene_name: "#005EB0", scene_description: "#475569" }
    },
    {
      id: "slot_1",
      label: "ЛЕВЫЙ ВЕРХ",
      icon: "⬛",
      slot_class: "slot-1",
      x: 0.0, y: 0.0, w: 25.0, h: 58.0,
      default_lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"]
    },
    {
      id: "slot_3",
      label: "ПРАВЫЙ ВЕРХ",
      icon: "⬛",
      slot_class: "slot-3",
      x: 75.0, y: 0.0, w: 25.0, h: 58.0,
      default_lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"]
    },
    {
      id: "slot_2",
      label: "ЛЕВЫЙ НИЗ",
      icon: "⬛",
      slot_class: "slot-2",
      x: 0.0, y: 58.0, w: 25.0, h: 36.0,
      default_lines: ["workflow_history", "workflow_stadia"]
    },
    {
      id: "slot_4",
      label: "ПРАВЫЙ НИЗ",
      icon: "⬛",
      slot_class: "slot-4",
      x: 75.0, y: 58.0, w: 25.0, h: 36.0,
      default_lines: ["workflow_history", "workflow_stadia"]
    },
    {
      id: "footer",
      label: "ПОДВАЛ",
      icon: "📑",
      slot_class: "slot-footer",
      x: 0.0, y: 94.0, w: 100.0, h: 6.0,
      default_lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"],
      default_line_aligns: {
        footer_last_edit: "left",
        footer_ver_rev: "center",
        footer_articul: "center",
        footer_date: "center",
        footer_page_total: "right"
      }
    }
  ];

  // Available Information Lines that can be toggled on/off in each block
  const AVAILABLE_INFO_LINES = [
    { key: "toc_pages",        group: "project",  label: "Содержание (список страниц)", icon: "📑", getVal: (info, wf) => {
        const sc = (state.scenes || []).filter(s => s.enabled !== false && s.page_type !== "skip");
        const total = sc.length;
        return total > 0 ? `(всего страниц: ${total}) ` + sc.map((s, i) => `${i + 1}. ${s.name}`).join(" • ") : "Список страниц проекта (0 страниц)";
      }
    },
    { key: "spec_materials",   group: "specs",    label: "Материалы и фурнитура",   icon: "🛠️", getVal: (info, wf) => (info.materials || "").trim() },
    { key: "spec_appliances",  group: "specs",    label: "Техника и подсветка",     icon: "🔌", getVal: (info, wf) => [info.appliances, info.lighting].filter(Boolean).map(s => s.trim()).filter(Boolean).join("; ") },
    { key: "general_notes",    group: "project",  label: "Общие пояснения",         icon: "📝", getVal: (info, wf) => (info.project_description || info.description || info.notes || "").trim() },
    { key: "workflow_history", group: "workflow", label: "История правок",          icon: "📜", getVal: (info, wf) => {
        const h = wf.history_edit || info.history_edit;
        if (Array.isArray(h) && h.length > 0) {
          return h.map(e => Array.isArray(e) ? `${e[0]} ${e[1]}` : String(e)).join(" • ");
        }
        return (wf.last_edit || info.last_edit || "").trim();
      }
    },
    { key: "workflow_stadia",  group: "workflow", label: "Стадия проекта",          icon: "⏳", getVal: (info, wf) => {
        const s = wf.stadia || info.stadia;
        if (Array.isArray(s) && s.length > 0) {
          return s.map(st => Array.isArray(st) ? `${st[1] ? "[✓]" : "[ ]"} ${st[2]}` : String(st)).join(" • ");
        }
        return (wf.status || info.status || "").trim();
      }
    },
    { key: "workflow_revision",group: "workflow", label: "Ревизия",                 icon: "🏷️", getVal: (info, wf) => `Ревизия ${wf.revision || info.revision || '001'}` },
    { key: "workflow_version", group: "workflow", label: "Версия",                  icon: "🔢", getVal: (info, wf) => `Версия ${wf.version || info.version || '01'}` },
    { key: "workflow_date",    group: "workflow", label: "Дата",                    icon: "🗓️", getVal: (info, wf) => {
        const d = wf.last_edit_date || info.date || info.created_date;
        return d ? String(d).trim() : new Date().toLocaleDateString();
      }
    },
    { key: "articul",          group: "project",  label: "Артикул",                 icon: "🔖", getVal: (info, wf) => (info.articul || "").trim() || "CF#260905_160129_01" },
    { key: "furniture_name",   group: "project",  label: "Название мебели",         icon: "🪑", getVal: (info, wf) => (info.furniture_name || info.name_product || "").trim() || "Шкаф, Тумба, Зеркало" },
    { key: "place_address",    group: "project",  label: "Место установки | Адрес установки", icon: "📍", getVal: (info, wf) => [info.room_name || info.name_place, info.address || info.adress].filter(Boolean).map(s => s.trim()).join(" | ") || "Санузел у бани | г. Москва" },
    { key: "customer_or_company", group: "customer", label: "Имя заказчика или Название компании", icon: "👤", getVal: (info, wf) => [info.name_customer || info.customer, info.company || info.name_company].filter(Boolean).map(s => s.trim()).join(" | ") || "Смирнов С.С. | ООО «МебельПроект»" },
    { key: "footer_last_edit", group: "system",   label: "Последние изменения",     icon: "📝", getVal: (info, wf) => {
        const h = wf.history_edit || info.history_edit;
        const last = Array.isArray(h) && h.length > 0 ? (Array.isArray(h[h.length - 1]) ? `${h[h.length - 1][0]} ${h[h.length - 1][1]}` : h[h.length - 1]) : (wf.last_edit || info.last_edit || "");
        const s = String(last).trim();
        return s ? (s.toLowerCase().startsWith("последние") ? s : `Последние изменения: ${s}`) : "Последние изменения: —";
      }
    },
    { key: "footer_ver_rev",   group: "system",   label: "Версия # Ревизия",        icon: "🔢", getVal: (info, wf) => {
        const ver = wf.version || info.version || '01';
        const rev = wf.revision || info.revision || '001';
        return `Версия ${ver} # Ревизия ${rev}`;
      }
    },
    { key: "footer_articul",   group: "system",   label: "Артикул",                 icon: "🔖", getVal: (info, wf) => {
        const art = (info.articul || '').trim() || 'CF#260905_160129_01';
        return art.toLowerCase().startsWith("артикул") ? art : `Артикул: ${art}`;
      }
    },
    { key: "footer_date",      group: "system",   label: "Дата",                    icon: "🗓️", getVal: (info, wf) => {
        const d = (wf.last_edit_date || info.date || '').trim() || new Date().toLocaleDateString();
        return d.toLowerCase().startsWith("дата") ? d : `Дата: ${d}`;
      }
    },
    { key: "footer_page_total",group: "system",   label: "Страница Страниц",        icon: "📄", getVal: () => "Страница 1 | 4" },
    { key: "footer_rev_ver_date", group: "system", label: "Ревизия # Версия | Артикул | Дата", icon: "🗓️", getVal: (info, wf) => {
        const rev = wf.revision || info.revision || '001';
        const ver = wf.version || info.version || '01';
        const art = (info.articul || '').trim() || 'CF#260905_160129_01';
        return `Ревизия ${rev} # Версия ${ver} | ${art} | ${new Date().toLocaleDateString()}`;
      }
    },
    { key: "project_desc",     group: "project",  label: "Описание задания",        icon: "📋", getVal: (info, wf) => (info.project_description || info.description || "").trim() },
    { key: "workflow_status",  group: "workflow", label: "Статус проекта",          icon: "⏳", getVal: (info, wf) => (wf.status || info.status || "").trim() },
    { key: "room_name",        group: "project",  label: "Помещение",               icon: "🚪", getVal: (info, wf) => (info.room_name || info.name_place || "").trim() },
    { key: "address",          group: "project",  label: "Адрес установки",        icon: "📍", getVal: (info, wf) => (info.address || info.adress || "").trim() },
    { key: "customer_name",    group: "customer", label: "Заказчик / Контакт",      icon: "👤", getVal: (info, wf) => (info.name_customer || info.customer || "").trim() },
    { key: "customer_phone",   group: "customer", label: "Телефон",                 icon: "📞", getVal: (info, wf) => (info.phone || "").trim() },
    { key: "customer_email",   group: "customer", label: "Email",                   icon: "✉️", getVal: (info, wf) => (info.email || "").trim() },
    { key: "customer_company", group: "customer", label: "Компания заказчика",      icon: "🏢", getVal: (info, wf) => (info.company || info.name_company || "").trim() },
    { key: "workflow_dates",   group: "workflow", label: "Сроки (Начало — Сдача)",  icon: "📅", getVal: (info, wf) => (info.start_date || info.end_date) ? `${info.start_date || "—"} → ${info.end_date || "—"}` : "" },
    { key: "workflow_price",   group: "workflow", label: "Стоимость проекта",       icon: "💰", getVal: (info, wf) => info.price ? `${info.price} руб.` : "" },
    { key: "workflow_author",  group: "workflow", label: "Автор / Конструктор",     icon: "👷", getVal: (info, wf) => (wf.author || info.author || "").trim() },
    { key: "scene_notes",      group: "specs",    label: "Примечание к сцене",      icon: "📝", getVal: (info, wf) => (info.notes || "").trim() },
    { key: "scene_name",        group: "project",  label: "Название Сцены",          icon: "📐", getVal: (info, wf) => {
        const sc = (layoutState.selectedSceneIndex !== undefined && state.scenes[layoutState.selectedSceneIndex])
          ? state.scenes[layoutState.selectedSceneIndex]
          : ((state.scenes || []).find(s => s.page_type === (layoutState.currentTemplate || "cover")) || (state.scenes || [])[0]);
        return (sc?.name || sc?.original_name || "01. Сцена SketchUp").trim();
      }
    },
    { key: "scene_description", group: "project",  label: "Описание Сцены",          icon: "📝", getVal: (info, wf) => {
        const sc = (layoutState.selectedSceneIndex !== undefined && state.scenes[layoutState.selectedSceneIndex])
          ? state.scenes[layoutState.selectedSceneIndex]
          : ((state.scenes || []).find(s => s.page_type === (layoutState.currentTemplate || "cover")) || (state.scenes || [])[0]);
        return (sc?.description || "").trim();
      }
    }
  ];

  const DEFAULT_LINES_BY_CONTENT = {
    slot_1: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"],
    slot_3: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"],
    slot_2: ["workflow_history", "workflow_stadia"],
    slot_4: ["workflow_history", "workflow_stadia"],
    header: ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"],
    footer: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"]
  };

  const DEFAULT_HEADER_SLOT = {
    visible: true,
    align: "center",
    valign: "center",
    font_size: 11,
    lines: ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"],
    line_rows: { furniture_name: 1, place_address: 2, customer_or_company: 3, scene_name: 4, scene_description: 5 },
    line_font_sizes: { furniture_name: 11, place_address: 10, customer_or_company: 10, scene_name: 11, scene_description: 9 },
    line_colors: { furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A", scene_name: "#005EB0", scene_description: "#475569" },
    opacity: 0.95
  };

  // Default block configurations for each page template
  const DEFAULT_LAYOUTS = {
    cover: {
      name: "Титульный лист (Cover)",
      slots: {
        header:    Object.assign({}, DEFAULT_HEADER_SLOT),
        image_4_3: { visible: true },
        slot_1:    { visible: true,  align: "left",   valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_2:    { visible: true,  align: "left",   valign: "bottom", font_size: 8,  lines: ["workflow_history", "workflow_stadia"], opacity: 0.9 },
        slot_3:    { visible: true,  align: "right",  valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_4:    { visible: true,  align: "right",  valign: "bottom", font_size: 8,  lines: ["workflow_history", "workflow_stadia"], opacity: 0.9 },
        footer:    { visible: true,  align: "center", valign: "center", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    description: {
      name: "Описание и спецификации (Description)",
      slots: {
        header:    Object.assign({}, DEFAULT_HEADER_SLOT),
        image_4_3: { visible: true },
        slot_1:    { visible: true,  align: "left",   valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_2:    { visible: true,  align: "left",   valign: "bottom", font_size: 8,  lines: ["workflow_history", "workflow_stadia"], opacity: 0.9 },
        slot_3:    { visible: true,  align: "right",  valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_4:    { visible: true,  align: "right",  valign: "bottom", font_size: 8,  lines: ["workflow_history", "workflow_stadia"], opacity: 0.9 },
        footer:    { visible: true,  align: "center", valign: "center", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    explain: {
      name: "Содержание и ведомость (Explain)",
      slots: {
        header:    Object.assign({}, DEFAULT_HEADER_SLOT),
        image_4_3: { visible: true },
        slot_1:    { visible: true,  align: "left",   valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_2:    { visible: false, align: "left",   valign: "bottom", font_size: 8,  lines: [], opacity: 0.9 },
        slot_3:    { visible: true,  align: "right",  valign: "top",    font_size: 8,  lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"], opacity: 0.9 },
        slot_4:    { visible: false, align: "right",  valign: "bottom", font_size: 8,  lines: [], opacity: 0.9 },
        footer:    { visible: true,  align: "center", valign: "center", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    general: {
      name: "Общий вид (General)",
      slots: {
        header:    Object.assign({}, DEFAULT_HEADER_SLOT),
        image_4_3: { visible: true },
        slot_1:    { visible: false, align: "left",   valign: "top",    font_size: 8,  lines: [], opacity: 0.88 },
        slot_2:    { visible: false, align: "left",   valign: "bottom", font_size: 8,  lines: [], opacity: 0.88 },
        slot_3:    { visible: false, align: "right",  valign: "top",    font_size: 8,  lines: [], opacity: 0.88 },
        slot_4:    { visible: true,  align: "right",  valign: "bottom", font_size: 8,  lines: ["workflow_history", "workflow_stadia"], opacity: 0.88 },
        footer:    { visible: true,  align: "center", valign: "center", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    visual: {
      name: "Визуализация (Visual)",
      slots: {
        header:    Object.assign({}, DEFAULT_HEADER_SLOT),
        image_4_3: { visible: true },
        slot_1:    { visible: false, align: "left",   valign: "top",    font_size: 8,  lines: [], opacity: 0.88 },
        slot_2:    { visible: false, align: "left",   valign: "bottom", font_size: 8,  lines: [], opacity: 0.88 },
        slot_3:    { visible: false, align: "right",  valign: "top",    font_size: 8,  lines: [], opacity: 0.88 },
        slot_4:    { visible: false, align: "right",  valign: "bottom", font_size: 8,  lines: [], opacity: 0.88 },
        footer:    { visible: true,  align: "center", valign: "center", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    }
  };

  // Layout Editor Internal State
  const layoutState = {
    currentTemplate: "cover",
    selectedBlockId: "slot_1",
    snapEnabled: true,
    snapGridPct: 2.0,
    guidesEnabled: true,
    zoomLevel: 1.0,
    openLinesPopoverBlockId: null
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

    // Tab 1 Inputs (Modular Project, Customer, Workflow)
    inputRoomName: document.getElementById("inputRoomName"),
    inputFurnitureName: document.getElementById("inputFurnitureName"),
    inputCustomer: document.getElementById("inputCustomer"),
    inputCustomerId: document.getElementById("inputCustomerId"),
    btnGenerateCustomerId: document.getElementById("btnGenerateCustomerId"),
    inputCompany: document.getElementById("inputCompany"),
    companyFieldGroup: document.getElementById("companyFieldGroup"),
    inputArticul: document.getElementById("inputArticul"),
    btnGenerateArticul: document.getElementById("btnGenerateArticul"),
    selectTrade: document.getElementById("selectTrade"),
    inputTags: document.getElementById("inputTags"),
    inputProjectDescription: document.getElementById("inputProjectDescription"),
    inputPhone: document.getElementById("inputPhone"),
    inputEmail: document.getElementById("inputEmail"),
    inputAddress: document.getElementById("inputAddress"),
    inputAuthor: document.getElementById("inputAuthor"),
    inputPrice: document.getElementById("inputPrice"),
    inputStartDate: document.getElementById("inputStartDate"),
    inputEndDate: document.getElementById("inputEndDate"),
    inputTotalDuration: document.getElementById("inputTotalDuration"),
    inputVersion: document.getElementById("inputVersion"),
    inputRevision: document.getElementById("inputRevision"),
    inputStatus: document.getElementById("inputStatus"),
    inputLastEdit: document.getElementById("inputLastEdit"),

    // Tab Directories
    directoriesCardsContainer: document.getElementById("directoriesCardsContainer"),
    btnAddDirectory: document.getElementById("btnAddDirectory"),

    // Tab Settings
    apiTargetsList: document.getElementById("apiTargetsList"),

    // Tab 2 Elements: Scenes & Layout Split View
    layoutTplUsageBadge: document.getElementById("layoutTplUsageBadge"),
    scenesTableBody: document.getElementById("scenesTableBody"),
    btnSelectAllScenes: document.getElementById("btnSelectAllScenes"),
    btnDeselectAllScenes: document.getElementById("btnDeselectAllScenes"),
    btnAutoMapScenes: document.getElementById("btnAutoMapScenes"),
    scenesPanel: document.getElementById("scenesPanel"),
    scenesSplitResizer: document.getElementById("scenesSplitResizer"),

    // Template & List Settings Elements
    templateSettingsPanel: document.getElementById("templateSettingsPanel"),
    templateSettingsContainer: document.getElementById("templateSettingsContainer"),
    selectLayoutTemplate: document.getElementById("selectLayoutTemplate"),
    layoutPageInfoBadge: document.getElementById("layoutPageInfoBadge"),
    inputLayoutMargin: document.getElementById("inputLayoutMargin"),
    btnResetLayout: document.getElementById("btnResetLayout"),

    // Tab 3 Inputs
    selectExportEngine: document.getElementById("selectExportEngine"),
    engineHintText: document.getElementById("engineHintText"),
    layoutRenderModeGroup: document.getElementById("layoutRenderModeGroup"),
    selectLayoutRenderMode: document.getElementById("selectLayoutRenderMode"),
    layoutSaveFileGroup: document.getElementById("layoutSaveFileGroup"),
    chkSaveLayoutFile: document.getElementById("chkSaveLayoutFile"),
    selectPageSize: document.getElementById("selectPageSize"),
    selectPageLayout: document.getElementById("selectPageLayout"),
    inputPageMargin: document.getElementById("inputPageMargin"),
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
      if (action === "getFolderFiles") {
        try {
          const p = typeof param === "string" ? JSON.parse(param) : param;
          setTimeout(() => {
            if (window.app && window.app.onFolderFilesLoaded) {
              window.app.onFolderFilesLoaded({
                index: p.index,
                path: p.path,
                exists: true,
                full_path: p.path,
                files: [
                  { name: "photo_preview_01.jpg", path: p.path + "/photo_01.jpg", url: "", size: 245760, ext: "JPG", is_image: true },
                  { name: "room_dimension_plan.pdf", path: p.path + "/plan.pdf", url: "", size: 524288, ext: "PDF", is_image: false }
                ]
              });
            }
          }, 400);
        } catch (e) {}
      }
    }
  }

  // Navigation Tabs Switching
  function setupTabs() {
    const appContent = document.querySelector(".app-content");
    const tabs = document.querySelectorAll(".tab-btn");
    const tabPanes = document.querySelectorAll(".tab-pane");
    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        tabs.forEach((t) => t.classList.remove("active"));
        tabPanes.forEach((p) => p.classList.remove("active"));

        tab.classList.add("active");
        if (appContent) {
          appContent.classList.toggle("no-padding", tab.dataset.tab === "tab-scenes");
        }
        const targetPane = document.getElementById(tab.dataset.tab);
        if (targetPane) {
          targetPane.classList.add("active");
          if (tab.dataset.tab === "tab-scenes") {
            renderScenesTable();
            renderLayoutCanvas();
            updateLayoutUsageBadge();
          } else if (tab.dataset.tab === "tab-directories") {
            renderDirectories();
          } else if (tab.dataset.tab === "tab-settings") {
            renderApiTargets();
          }
        }
      });
    });
  }

  function updateLayoutUsageBadge() {
    const badge = els.layoutTplUsageBadge || document.getElementById("layoutTplUsageBadge");
    const tplKey = layoutState.currentTemplate;

    if (badge) {
      const scenes = state.scenes || [];
      const matching = scenes.filter((s) => s.page_type === tplKey);
      if (matching.length > 0) {
        const names = matching.map((s) => s.name).join(", ");
        badge.textContent = `Используется: ${names}`;
        badge.style.display = "inline-flex";
      } else {
        badge.textContent = "Не привязан к сценам";
        badge.style.display = "inline-flex";
      }
    }

    // Highlight matching row in scenes table
    if (els.scenesTableBody) {
      const rows = els.scenesTableBody.querySelectorAll("tr");
      rows.forEach((tr) => {
        const sel = tr.querySelector(".table-select");
        if (sel) {
          tr.classList.toggle("active-split-scene", sel.value === tplKey);
        }
      });
    }
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
  // Fixed Slot Layout Editor Engine
  // -----------------------------------------------------------------------------

  function ensureCustomLayouts() {
    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};

    const validSlotIds = new Set(FIXED_SLOT_DEFS.map((s) => s.id));

    Object.keys(DEFAULT_LAYOUTS).forEach((tplKey) => {
      if (!state.pdf_settings.custom_layouts[tplKey]) {
        state.pdf_settings.custom_layouts[tplKey] = {};
      }

      // Purge legacy keys (e.g. cover_accent_bar, cover_hero_image, desc_header, etc.)
      Object.keys(state.pdf_settings.custom_layouts[tplKey]).forEach((k) => {
        if (!validSlotIds.has(k)) {
          delete state.pdf_settings.custom_layouts[tplKey][k];
        }
      });

      const tplDefaults = DEFAULT_LAYOUTS[tplKey]?.slots || {};
      FIXED_SLOT_DEFS.forEach((slotDef) => {
        const current = state.pdf_settings.custom_layouts[tplKey][slotDef.id];
        const defSlot = tplDefaults[slotDef.id] || {};
        const defContent = defSlot.content || slotDef.default_content || "none";
        const defFontSize = defSlot.font_size !== undefined ? defSlot.font_size : (slotDef.id === "header" ? 11 : (slotDef.id === "footer" ? 8.5 : 8));
        const defLines = defSlot.lines ? [...defSlot.lines] : [...(DEFAULT_LINES_BY_CONTENT[slotDef.id] || DEFAULT_LINES_BY_CONTENT[defContent] || slotDef.default_lines || [])];
        const defLineRows = defSlot.line_rows ? Object.assign({}, defSlot.line_rows) : (slotDef.default_line_rows ? Object.assign({}, slotDef.default_line_rows) : null);
        const defLineFontSizes = defSlot.line_font_sizes ? Object.assign({}, defSlot.line_font_sizes) : (slotDef.default_line_font_sizes ? Object.assign({}, slotDef.default_line_font_sizes) : null);
        const defLineColors = defSlot.line_colors ? Object.assign({}, defSlot.line_colors) : (slotDef.default_line_colors ? Object.assign({}, slotDef.default_line_colors) : null);
        const defLineAligns = defSlot.line_aligns ? Object.assign({}, defSlot.line_aligns) : (slotDef.default_line_aligns ? Object.assign({}, slotDef.default_line_aligns) : null);

        if (!current) {
          state.pdf_settings.custom_layouts[tplKey][slotDef.id] = {
            visible: defSlot.visible !== false,
            content: defContent,
            custom_text: defSlot.custom_text || "",
            align: defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left"),
            font_size: defFontSize,
            lines: defLines,
            line_rows: defLineRows,
            line_font_sizes: defLineFontSizes,
            line_colors: defLineColors,
            line_aligns: defLineAligns,
            opacity: defSlot.opacity !== undefined ? defSlot.opacity : 0.9
          };
        } else {
          if (current.visible === undefined) current.visible = defSlot.visible !== false;
          if (!current.content || (current.content === "none" && defSlot.content && defSlot.content !== "none" && !current.explicit_none)) {
            current.content = defContent;
          }
          if (!current.align) current.align = defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left");
          if (current.font_size === undefined) current.font_size = defFontSize;
          if (!current.lines) current.lines = defLines;
          if (slotDef.id === "header") {
            if (!current.line_rows) current.line_rows = defLineRows;
            if (!current.line_font_sizes) current.line_font_sizes = defLineFontSizes;
            if (!current.line_colors) current.line_colors = defLineColors;
          }
          if (slotDef.id === "footer" && !current.line_aligns) current.line_aligns = defLineAligns;
          if (current.opacity === undefined) current.opacity = defSlot.opacity !== undefined ? defSlot.opacity : 0.9;
        }
      });
    });
  }

  function getActiveLayoutBlocks() {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate;
    const tplDefaults = (DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS.cover).slots || {};
    const customTpl = state.pdf_settings.custom_layouts[tplKey] || {};

    return FIXED_SLOT_DEFS.map((slotDef) => {
      const custom = customTpl[slotDef.id] || {};
      const defSlot = tplDefaults[slotDef.id] || {};
      const content = custom.content || defSlot.content || slotDef.default_content || "none";
      const defaultLines = defSlot.lines ? [...defSlot.lines] : (DEFAULT_LINES_BY_CONTENT[slotDef.id] || DEFAULT_LINES_BY_CONTENT[content] || slotDef.default_lines || []);
      const defaultLineRows = defSlot.line_rows || slotDef.default_line_rows || null;
      const defaultLineFontSizes = defSlot.line_font_sizes || slotDef.default_line_font_sizes || null;
      const defaultLineColors = defSlot.line_colors || slotDef.default_line_colors || null;
      const defaultLineAligns = defSlot.line_aligns || slotDef.default_line_aligns || null;

      let customX = custom.x !== undefined ? parseFloat(custom.x) : (defSlot.x !== undefined ? parseFloat(defSlot.x) : slotDef.x);
      let customY = custom.y !== undefined ? parseFloat(custom.y) : (defSlot.y !== undefined ? parseFloat(defSlot.y) : slotDef.y);
      let customW = custom.w !== undefined ? parseFloat(custom.w) : (defSlot.w !== undefined ? parseFloat(defSlot.w) : slotDef.w);
      let customH = custom.h !== undefined ? parseFloat(custom.h) : (defSlot.h !== undefined ? parseFloat(defSlot.h) : slotDef.h);

      if (slotDef.id === "header") {
        customY = 0.0;
        customH = 30.0;
      }

      return {
        id: slotDef.id,
        label: slotDef.label,
        icon: slotDef.icon,
        slot_class: slotDef.slot_class,
        is_image: !!slotDef.is_image,
        x: customX,
        y: customY,
        w: customW,
        h: customH,
        visible: custom.visible !== undefined ? custom.visible : (defSlot.visible !== false),
        content: content,
        custom_text: custom.custom_text !== undefined ? custom.custom_text : (defSlot.custom_text || ""),
        align: custom.align || defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : (slotDef.id === "slot_3" || slotDef.id === "slot_4" ? "right" : "left")),
        font_size: custom.font_size !== undefined ? custom.font_size : (defSlot.font_size !== undefined ? defSlot.font_size : (slotDef.id === "header" ? 11 : (slotDef.id === "footer" ? 8.5 : 8))),
        lines: custom.lines ? [...custom.lines] : (defSlot.lines ? [...defSlot.lines] : [...defaultLines]),
        line_rows: custom.line_rows ? Object.assign({}, custom.line_rows) : (defaultLineRows ? Object.assign({}, defaultLineRows) : null),
        line_font_sizes: custom.line_font_sizes ? Object.assign({}, custom.line_font_sizes) : (defaultLineFontSizes ? Object.assign({}, defaultLineFontSizes) : null),
        line_colors: custom.line_colors ? Object.assign({}, custom.line_colors) : (defaultLineColors ? Object.assign({}, defaultLineColors) : null),
        line_aligns: custom.line_aligns ? Object.assign({}, custom.line_aligns) : (defaultLineAligns ? Object.assign({}, defaultLineAligns) : null),
        opacity: custom.opacity !== undefined ? custom.opacity : (defSlot.opacity !== undefined ? defSlot.opacity : 0.9),
        content_options: slotDef.content_options || null
      };
    });
  }

  function getBlockData(blockId) {
    const blocks = getActiveLayoutBlocks();
    return blocks.find((b) => b.id === blockId) || null;
  }

  function updateBlockSlot(blockId, updates) {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate;
    if (!state.pdf_settings.custom_layouts[tplKey]) {
      state.pdf_settings.custom_layouts[tplKey] = {};
    }
    if (!state.pdf_settings.custom_layouts[tplKey][blockId]) {
      state.pdf_settings.custom_layouts[tplKey][blockId] = {};
    }
    if (blockId === "header") {
      updates.y = 0.0;
      updates.h = 30.0;
    }
    Object.assign(state.pdf_settings.custom_layouts[tplKey][blockId], updates);
  }

  function updateHeaderHeight(newH) {
    updateBlockSlot("header", { y: 0.0, h: 30.0 });
  }

  function updateColumnWidthFromEdge(side, widthPct) {
    widthPct = Math.max(10, Math.min(80, Math.round(parseFloat(widthPct) * 10) / 10));
    if (isNaN(widthPct)) return;

    if (side === "left") {
      updateBlockSlot("slot_1", { x: 0.0, w: widthPct, align: "left" });
      updateBlockSlot("slot_2", { x: 0.0, w: widthPct, align: "left" });
    } else if (side === "right") {
      const rightX = Math.round((100 - widthPct) * 10) / 10;
      updateBlockSlot("slot_3", { x: rightX, w: widthPct, align: "right" });
      updateBlockSlot("slot_4", { x: rightX, w: widthPct, align: "right" });
    }
  }

  function updateColumnWidth(newW) {
    newW = Math.max(10, Math.min(80, Math.round(newW * 10) / 10));
    updateColumnWidthFromEdge("left", newW);
    updateColumnWidthFromEdge("right", newW);
  }

  function getContentLabel(contentKey) {
    const allOptions = [
      { value: "header_title", label: "Заголовок" },
      { value: "render_viewport", label: "4:3 Рендер" },
      { value: "footer_info", label: "Подвал" },
      ...SLOT_STANDARD_CONTENT_OPTIONS
    ];
    const found = allOptions.find((o) => o.value === contentKey);
    return found ? found.label.replace(/^[^a-zA-Zа-яА-Я0-9]+/, "") : contentKey;
  }

  // Generate live content preview for a block on the virtual sheet
  function generateBlockPreviewHtml(blk) {
    const info = state.project_info || {};
    const wf = state.workflow || {};
    const align = blk.align || (blk.id === "header" || blk.id === "footer" ? "center" : "left");
    const fontSize = blk.font_size !== undefined ? parseFloat(blk.font_size) : (blk.id === "header" ? 11 : (blk.id === "footer" ? 8.5 : 8));
    const titleSize = Math.min(22, Math.max(7, fontSize + 1.5));

    if (blk.id === "image_4_3") {
      if (!blk.visible || blk.content === "none") {
        return `<div class="block-image-placeholder" style="opacity: 0.4;"><span>⚪ Видовой экран отключен</span></div>`;
      }
      return `
        <div class="block-image-placeholder">
          <div class="image-aspect-badge">📐 4:3 РЕНДЕР МОДЕЛИ</div>
          <div class="image-subnote">Центральный видовой экран сцены SketchUp</div>
        </div>
      `;
    }

    // Active lines for this block
    const activeLines = Array.isArray(blk.lines)
      ? blk.lines
      : (DEFAULT_LINES_BY_CONTENT[blk.content] || []);

    if (blk.id === "header") {
      const headerValign = blk.valign || "center";
      const justifyVal = headerValign === "top" ? "flex-start" : (headerValign === "bottom" ? "flex-end" : "center");

      if (blk.content === "custom_text") {
        return `
          <div style="text-align: center; overflow: hidden; display: flex; flex-direction: column; justify-content: ${justifyVal}; height: 100%;">
            <div style="font-size: ${fontSize}px; font-weight: 700; color: #005EB0; font-stretch: extra-condensed; letter-spacing: -0.025em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${blk.custom_text || "Пользовательский заголовок страницы"}</div>
          </div>
        `;
      }
      if (blk.content === "none") {
        return `<div style="font-size: ${Math.max(7, fontSize - 2)}px; color: #94a3b8; font-style: italic; text-align: center;">(Заголовок скрыт)</div>`;
      }

      const lineRows = blk.line_rows || {
        furniture_name: 1,
        place_address: 2,
        customer_or_company: 3,
        scene_name: 4,
        scene_description: 5
      };
      const lineFontSizes = blk.line_font_sizes || {
        furniture_name: 11,
        place_address: 10,
        customer_or_company: 10,
        scene_name: 11,
        scene_description: 9
      };
      const lineColors = blk.line_colors || {
        furniture_name: "#005EB0",
        place_address: "#0F172A",
        customer_or_company: "#0F172A",
        scene_name: "#005EB0",
        scene_description: "#475569"
      };
      const sampleFurn = (info.furniture_name || info.name_product || "Шкаф, Тумба").trim();
      const sampleRoom = (info.room_name || info.name_place || "Прихожая").trim();
      const sampleAddr = (info.address || info.adress || "Адрес объекта").trim();
      const sampleCust = (info.company || info.name_customer || info.customer || "Заказчик").trim();

      const activeTpl = layoutState.currentTemplate || "cover";
      const matchingScene = (layoutState.selectedSceneIndex !== undefined && state.scenes[layoutState.selectedSceneIndex] && state.scenes[layoutState.selectedSceneIndex].page_type === activeTpl)
        ? state.scenes[layoutState.selectedSceneIndex]
        : ((state.scenes || []).find((s) => s.page_type === activeTpl) || (state.scenes || [])[0]);
      const sampleSceneName = (matchingScene?.name || matchingScene?.original_name || "01. Обложка").trim();
      const sampleSceneDesc = (matchingScene?.description || "").trim();

      const getHeaderItemVal = (k) => {
        if (k === "furniture_name") return sampleFurn;
        if (k === "place_address") return [sampleRoom, sampleAddr].filter(Boolean).join(" | ") || "Место | Адрес";
        if (k === "customer_or_company") return sampleCust;
        if (k === "scene_name" || k === "name" || k === "name_scene") return sampleSceneName;
        if (k === "scene_description" || k === "description" || k === "scene_desc" || k === "desc") return sampleSceneDesc;
        const lineDef = AVAILABLE_INFO_LINES.find((l) => l.key === k);
        return lineDef ? lineDef.getVal(info, wf) : "";
      };

      const grouped = { 1: [], 2: [], 3: [], 4: [], 5: [] };
      activeLines.forEach((k, idx) => {
        const defaultR = k === "furniture_name" ? 1 : (k === "place_address" ? 2 : (k === "customer_or_company" ? 3 : (k === "scene_name" ? 4 : (k === "scene_description" ? 5 : Math.min(idx + 1, 5)))));
        const row = parseInt(lineRows[k] || defaultR, 10);
        const targetRow = Math.max(1, Math.min(5, isNaN(row) ? 1 : row));
        const val = getHeaderItemVal(k);
        if (val) {
          const itemFs = parseFloat(lineFontSizes[k] || fontSize);
          const itemCol = (lineColors[k] || "#005EB0").trim();
          grouped[targetRow].push({ text: val, size: itemFs, color: itemCol });
        }
      });

      const renderedLines = [];
      [1, 2, 3, 4, 5].forEach((r) => {
        if (grouped[r].length > 0) {
          renderedLines.push(grouped[r]);
        }
      });

      if (renderedLines.length === 0) {
        renderedLines.push([
          { text: sampleFurn, size: fontSize, color: "#005EB0" },
          { text: [sampleRoom, sampleAddr].filter(Boolean).join(" | "), size: Math.max(7, fontSize - 1), color: "#0F172A" },
          { text: sampleCust, size: Math.max(7, fontSize - 1), color: "#0F172A" }
        ]);
      }

      const linesHtml = renderedLines.map((rowItems, idx) => {
        const sep = (idx < renderedLines.length - 1)
          ? `<div style="width: 45%; max-width: 130px; height: 1px; background: #CBD5E1; margin: 5px auto;"></div>`
          : ``;
        const itemsContent = rowItems.map((it, i) => {
          const s = (i > 0) ? `<span style="color: #CBD5E1; margin: 0 4px; font-weight: 700;">|</span>` : ``;
          return `${s}<span style="font-size: ${it.size}px; color: ${it.color}; font-weight: 700;">${it.text}</span>`;
        }).join("");
        return `<div style="font-stretch: extra-condensed; letter-spacing: -0.025em; text-overflow: ellipsis; white-space: nowrap; overflow: hidden; line-height: 1.4; padding: 2px 0;">${itemsContent}</div>${sep}`;
      }).join("");

      return `
        <div style="text-align: center; overflow: hidden; display: flex; flex-direction: column; justify-content: ${justifyVal}; height: 100%;">
          ${linesHtml}
        </div>
      `;
    }

    if (blk.id === "footer") {
      if (blk.content === "custom_text") {
        return `<div style="font-size: ${fontSize}px; color: #64748B; text-align: ${align}; font-stretch: extra-condensed; letter-spacing: -0.025em;">${blk.custom_text || "Пользовательский подвал"}</div>`;
      }
      if (blk.content === "none") {
        return `<div style="font-size: ${Math.max(7, fontSize - 2)}px; color: #94a3b8; font-style: italic; text-align: center;">(Подвал скрыт)</div>`;
      }

      const defaultAligns = {
        footer_last_edit: "left",
        footer_ver_rev: "center",
        footer_articul: "center",
        footer_date: "center",
        footer_page_total: "right"
      };
      const lineAligns = blk.line_aligns || defaultAligns;

      const leftItems = [];
      const centerItems = [];
      const rightItems = [];

      activeLines.forEach((lineKey) => {
        let actualKeys = [lineKey];
        if (lineKey === "footer_rev_ver_date") {
          actualKeys = ["footer_ver_rev", "footer_articul", "footer_date"];
        }
        actualKeys.forEach((k) => {
          const lineDef = AVAILABLE_INFO_LINES.find((l) => l.key === k);
          if (!lineDef) return;
          const val = lineDef.getVal(info, wf);
          if (!val && val !== 0) return;
          const itAlign = lineAligns[k] || defaultAligns[k] || "center";
          if (itAlign === "left") leftItems.push(val);
          else if (itAlign === "right") rightItems.push(val);
          else centerItems.push(val);
        });
      });

      if (leftItems.length === 0 && centerItems.length === 0 && rightItems.length === 0) {
        leftItems.push("Последние изменения: —");
        centerItems.push(`Версия ${wf.version || '01'} # Ревизия ${wf.revision || '001'}   |   Артикул: ${info.articul || 'CF#...'}   |   ${new Date().toLocaleDateString()}`);
        rightItems.push("Страница 1 | 4");
      }

      return `
        <div style="font-size: ${fontSize}px; color: #64748B; font-stretch: extra-condensed; letter-spacing: -0.025em; display: flex; justify-content: space-between; align-items: center; width: 100%; height: 100%; overflow: hidden; white-space: nowrap; padding: 0 4px; box-sizing: border-box; gap: 8px;">
          <div style="flex: 1; text-align: left; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${leftItems.join("   |   ")}</div>
          <div style="flex: 1.2; text-align: center; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${centerItems.join("   |   ")}</div>
          <div style="flex: 0.8; text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${rightItems.join("   |   ")}</div>
        </div>
      `;
    }

    if (blk.content === "none") {
      return `<div style="font-size: ${Math.max(7, fontSize - 1)}px; color: #94a3b8; font-style: italic; text-align: center; margin-top: 10px;">(Пустой слот)</div>`;
    }

    if (blk.content === "custom_text") {
      return `
        <div style="font-size: ${fontSize}px; color: #334155; text-align: ${align}; font-stretch: extra-condensed; letter-spacing: -0.025em; line-height: 1.35; white-space: pre-wrap;">
          ${blk.custom_text || "Произвольный текст блока..."}
        </div>
      `;
    }

    // Card titles for standard content blocks
    const cardTitles = {
      project_card:    "📋 ПАСПОРТ ОБЪЕКТА",
      customer_card:   "👤 ЗАКАЗЧИК",
      workflow_status: "⏱️ СТАТУС И СРОКИ",
      history_table:   "📜 ИСТОРИЯ ИЗМЕНЕНИЙ",
      materials_spec:  "🛠️ МАТЕРИАЛЫ",
      appliances_spec: "🔌 ТЕХНИКА",
      lighting_spec:   "💡 ПОДСВЕТКА",
      scene_notes:     "📝 ПРИМЕЧАНИЕ К ВИДУ",
      info_lines:      "📑 РЕКВИЗИТЫ ПРОЕКТА"
    };
    const titleText = cardTitles[blk.content] || "ИНФОРМАЦИЯ";

    // Build rendered lines
    let renderedLinesHtml = "";
    if (activeLines.length > 0) {
      renderedLinesHtml = activeLines.map((lineKey) => {
        const lineDef = AVAILABLE_INFO_LINES.find((l) => l.key === lineKey);
        if (!lineDef) return "";
        const val = lineDef.getVal(info, wf);
        if (!val && val !== 0) return "";
        return `<div><b>${lineDef.label}:</b> ${val}</div>`;
      }).filter(Boolean).join("");
    }

    // Fallback if no lines or empty
    if (!renderedLinesHtml) {
      renderedLinesHtml = `<div style="color: #94a3b8; font-style: italic;">(Нет отмеченных строк)</div>`;
    }

    return `
      <div style="font-weight: 700; color: #005EB0; font-size: ${titleSize}px; font-stretch: extra-condensed; letter-spacing: -0.025em; margin-bottom: 3px; text-align: ${align};">
        ${titleText}
      </div>
      <div style="font-size: ${fontSize}px; color: #334155; line-height: 1.35; font-stretch: extra-condensed; letter-spacing: -0.025em; text-align: ${align};">
        ${renderedLinesHtml}
      </div>
    `;
  }



  // -----------------------------------------------------------------------------
  // Template & List Settings Engine (Replaces Virtual Canvas with List Controls)
  // -----------------------------------------------------------------------------

  const HEADER_FONT_SIZES = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 46, 52];
  const BLOCK_FONT_SIZES = [8, 10, 12, 14, 16, 18];
  const HEADER_LINE_FONT_SIZES = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 46, 52];
  const HEADER_COLOR_PALETTE = [
    { value: "#005EB0", label: "Синий фирменный", dot: "🔵" },
    { value: "#0F172A", label: "Темный графит",   dot: "⚫" },
    { value: "#000000", label: "Черный",          dot: "⬛" },
    { value: "#1E293B", label: "Темно-серый",      dot: "🌑" },
    { value: "#475569", label: "Серый",           dot: "🔘" },
    { value: "#64748B", label: "Светло-серый",    dot: "⚪" },
    { value: "#2563EB", label: "Ярко-синий",      dot: "🔷" },
    { value: "#0284C7", label: "Голубой",         dot: "🔹" },
    { value: "#0D9488", label: "Бирюзовый",       dot: "🟢" },
    { value: "#16A34A", label: "Зеленый",         dot: "🟩" },
    { value: "#DC2626", label: "Красный",         dot: "🔴" },
    { value: "#EA580C", label: "Оранжевый",       dot: "🟧" },
    { value: "#7C3AED", label: "Фиолетовый",      dot: "🟣" },
    { value: "#B45309", label: "Охра / Бронза",   dot: "🟤" }
  ];

  function renderFontSizeOptions(currentVal, allowedSizes, defaultVal) {
    const cur = parseFloat(currentVal);
    let closest = allowedSizes[0];
    let minDiff = Infinity;
    for (const sz of allowedSizes) {
      const diff = Math.abs(cur - sz);
      if (diff < minDiff) {
        minDiff = diff;
        closest = sz;
      }
    }
    return allowedSizes.map((sz) => {
      const isSel = (sz === closest) ? ' selected' : '';
      const isDef = (defaultVal !== undefined && sz === defaultVal) ? ' (стандарт)' : '';
      return `<option value="${sz}"${isSel}>${sz} pt${isDef}</option>`;
    }).join('');
  }

  function renderTemplateSettingsList() {
    if (!els.templateSettingsContainer) return;
    ensureCustomLayouts();

    const tplKey = layoutState.currentTemplate || "cover";
    const customTpl = state.pdf_settings.custom_layouts[tplKey] || {};
    const tplDef = DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS.cover;
    const info = state.project_info || {};
    const wf = state.workflow || {};

    // Page format badge
    const isPortrait = (els.selectPageLayout ? els.selectPageLayout.value : state.pdf_settings?.page_layout) === "portrait";
    const pageSize = (els.selectPageSize ? els.selectPageSize.value : state.pdf_settings?.page_size) || "A4";
    if (els.layoutPageInfoBadge) {
      els.layoutPageInfoBadge.textContent = `${pageSize} ${isPortrait ? "Книжная" : "Альбомная"}`;
    }

    // Margin input sync
    if (els.inputLayoutMargin) {
      const curMargin = state.pdf_settings?.margin_mm !== undefined ? state.pdf_settings.margin_mm : 5;
      els.inputLayoutMargin.value = curMargin;
    }

    updateLayoutUsageBadge();

    // Helper to get slot config
    const getSlot = (slotId) => {
      const def = tplDef.slots?.[slotId] || {};
      const custom = customTpl[slotId] || {};
      return Object.assign({}, def, custom);
    };

    const header = getSlot("header");
    const slot1 = getSlot("slot_1");
    const slot2 = getSlot("slot_2");
    const slot3 = getSlot("slot_3");
    const slot4 = getSlot("slot_4");
    const footer = getSlot("footer");
    const image43 = getSlot("image_4_3");

    // Current column widths from slot_1 (left edge) and slot_3 (right edge)
    const colWidthLeft = Math.round((slot1.w !== undefined ? slot1.w : 25) * 10) / 10;
    const colWidthRight = Math.round((slot3.w !== undefined ? slot3.w : 25) * 10) / 10;
    const headerHeight = 30.0;

    let html = "";

    // -------------------------------------------------------------
    // CARD 1: ЗАГОЛОВОК СТРАНИЦЫ (Header) - Left Column Row 1
    // -------------------------------------------------------------
    const headerLines = Array.isArray(header.lines) ? header.lines : ["furniture_name", "place_address", "customer_or_company"];
    const headerLineRows = header.line_rows || {};
    const headerLineFontSizes = header.line_font_sizes || {};
    const headerLineColors = header.line_colors || {};

    const getHdrRow = (k, def) => {
      const val = parseInt(headerLineRows[k], 10);
      return (val >= 1 && val <= 5) ? val : def;
    };
    const getHdrSize = (k, def) => {
      const val = parseFloat(headerLineFontSizes[k]);
      return (!isNaN(val) && val > 0) ? val : def;
    };
    const getHdrColor = (k, def) => {
      const val = (headerLineColors[k] || "").trim();
      return val || def;
    };

    const rowFurn = getHdrRow("furniture_name", 1);
    const sizeFurn = getHdrSize("furniture_name", 11);
    const colFurn = getHdrColor("furniture_name", "#005EB0");

    const rowPlace = getHdrRow("place_address", 2);
    const sizePlace = getHdrSize("place_address", 10);
    const colPlace = getHdrColor("place_address", "#0F172A");

    const rowCust = getHdrRow("customer_or_company", 3);
    const sizeCust = getHdrSize("customer_or_company", 10);
    const colCust = getHdrColor("customer_or_company", "#0F172A");

    const rowSceneName = getHdrRow("scene_name", 4);
    const sizeSceneName = getHdrSize("scene_name", 11);
    const colSceneName = getHdrColor("scene_name", "#005EB0");

    const rowSceneDesc = getHdrRow("scene_description", 5);
    const sizeSceneDesc = getHdrSize("scene_description", 9);
    const colSceneDesc = getHdrColor("scene_description", "#475569");

    const headerFontSize = header.font_size !== undefined ? parseFloat(header.font_size) : 11;
    const headerValign = header.valign || "center";
    const isHeaderVis = header.visible !== false;

    const sampleFurn = (info.furniture_name || "Шкаф, Тумба").trim();
    const sampleRoom = (info.room_name || "Прихожая").trim();
    const sampleAddr = (info.address || "Адрес объекта").trim();
    const sampleCust = (info.company || info.name_customer || info.customer || "Заказчик").trim();

    const matchingScene = (layoutState.selectedSceneIndex !== undefined && state.scenes[layoutState.selectedSceneIndex] && state.scenes[layoutState.selectedSceneIndex].page_type === tplKey)
      ? state.scenes[layoutState.selectedSceneIndex]
      : ((state.scenes || []).find((s) => s.page_type === tplKey) || (state.scenes || [])[0]);
    const sampleSceneName = (matchingScene?.name || matchingScene?.original_name || "01. Обложка").trim();
    const sampleSceneDesc = (matchingScene?.description || "").trim();

    const renderHdrItemControls = (key, activeRow, activeSize, activeColor) => {
      let rowOptions = "";
      for (let r = 1; r <= 5; r++) {
        rowOptions += `<option value="${r}" ${activeRow === r ? 'selected' : ''}>${r}</option>`;
      }

      let sizeOptions = "";
      let matched = false;
      const roundedSize = Math.round(activeSize);
      HEADER_LINE_FONT_SIZES.forEach((sz) => {
        const isSel = (roundedSize === sz);
        if (isSel) matched = true;
        sizeOptions += `<option value="${sz}" ${isSel ? 'selected' : ''}>${sz} pt</option>`;
      });
      if (!matched && activeSize) {
        sizeOptions += `<option value="${activeSize}" selected>${activeSize} pt</option>`;
      }

      return `
        <div class="tpl-hdr-item-controls" data-key="${key}">
          <div class="tpl-hdr-param-box" title="Номер строки (1–5)">
            <select class="tpl-hdr-select sel-hdr-line-row" data-key="${key}">
              ${rowOptions}
            </select>
          </div>
          <div class="tpl-hdr-param-box" title="Размер шрифта строки (пт)">
            <select class="tpl-hdr-select sel-hdr-line-size" data-key="${key}">
              ${sizeOptions}
            </select>
          </div>
          <div class="tpl-hdr-param-box" title="Цвет текста строки">
            <input type="color" class="inp-hdr-line-color" data-key="${key}" value="${activeColor || '#0F172A'}" title="Цвет текста">
          </div>
        </div>
      `;
    };

    const cardHeaderHtml = `
      <div class="tpl-card tpl-panel-left ${!isHeaderVis ? 'disabled-card disabled-block' : ''}" id="card_header">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">🏛️</span>
            <span class="tpl-card-title">Заголовок страницы (Шапка)</span>
          </div>
          <div class="tpl-card-header-actions">
            <div class="tpl-header-valign-control">
              <span class="tpl-header-valign-label">По вертикали:</span>
              <div class="tpl-btn-group" id="grp_header_valign">
                <button type="button" class="tpl-btn-align ${headerValign === 'top' ? 'active' : ''}" data-valign="top" title="По верху">⬆</button>
                <button type="button" class="tpl-btn-align ${headerValign === 'center' ? 'active' : ''}" data-valign="center" title="По центру">↕</button>
                <button type="button" class="tpl-btn-align ${headerValign === 'bottom' ? 'active' : ''}" data-valign="bottom" title="По низу">⬇</button>
              </div>
            </div>
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin-left: 4px;">
              <input type="checkbox" id="chk_header_visible" ${isHeaderVis ? 'checked' : ''}>
              <span>Вкл</span>
            </label>
          </div>
        </div>
        <div class="tpl-card-body">
          <div>
            <div class="tpl-hdr-columns-header">
              <span class="tpl-hdr-col-title-lines">Выводимые строки заголовка:</span>
              <div class="tpl-hdr-col-titles">
                <span class="tpl-hdr-col-title col-row" title="Номер строки (1–5)">стр.</span>
                <span class="tpl-hdr-col-title col-size" title="Размер шрифта (пт)">пт.</span>
                <span class="tpl-hdr-col-title col-color" title="Цвет текста">цвет</span>
              </div>
            </div>
            <div class="tpl-lines-checklist">
              <div class="tpl-line-item tpl-hdr-line-row">
                <label class="tpl-hdr-label-wrap">
                  <input type="checkbox" class="chk-hdr-line" data-key="furniture_name" ${headerLines.includes("furniture_name") ? 'checked' : ''}>
                  <span class="tpl-line-label">🏷️ Название мебели / Изделие</span>
                  <span class="tpl-line-preview">(${sampleFurn})</span>
                </label>
                ${renderHdrItemControls("furniture_name", rowFurn, sizeFurn, colFurn)}
              </div>
              <div class="tpl-line-item tpl-hdr-line-row">
                <label class="tpl-hdr-label-wrap">
                  <input type="checkbox" class="chk-hdr-line" data-key="place_address" ${headerLines.includes("place_address") ? 'checked' : ''}>
                  <span class="tpl-line-label">🚪 Место установки | 📍 Адрес объекта</span>
                  <span class="tpl-line-preview">(${sampleRoom} | ${sampleAddr})</span>
                </label>
                ${renderHdrItemControls("place_address", rowPlace, sizePlace, colPlace)}
              </div>
              <div class="tpl-line-item tpl-hdr-line-row">
                <label class="tpl-hdr-label-wrap">
                  <input type="checkbox" class="chk-hdr-line" data-key="customer_or_company" ${headerLines.includes("customer_or_company") ? 'checked' : ''}>
                  <span class="tpl-line-label">👤 Имя заказчика или 🏢 Компания</span>
                  <span class="tpl-line-preview">(${sampleCust})</span>
                </label>
                ${renderHdrItemControls("customer_or_company", rowCust, sizeCust, colCust)}
              </div>
              <div class="tpl-line-item tpl-hdr-line-row">
                <label class="tpl-hdr-label-wrap">
                  <input type="checkbox" class="chk-hdr-line" data-key="scene_name" ${headerLines.includes("scene_name") ? 'checked' : ''}>
                  <span class="tpl-line-label">📐 Название Сцены</span>
                  <span class="tpl-line-preview">(${sampleSceneName})</span>
                </label>
                ${renderHdrItemControls("scene_name", rowSceneName, sizeSceneName, colSceneName)}
              </div>
              <div class="tpl-line-item tpl-hdr-line-row">
                <label class="tpl-hdr-label-wrap">
                  <input type="checkbox" class="chk-hdr-line" data-key="scene_description" ${headerLines.includes("scene_description") ? 'checked' : ''}>
                  <span class="tpl-line-label">📝 Описание Сцены</span>
                  <span class="tpl-line-preview">(${sampleSceneDesc || 'нет описания'})</span>
                </label>
                ${renderHdrItemControls("scene_description", rowSceneDesc, sizeSceneDesc, colSceneDesc)}
              </div>
            </div>
          </div>
        </div>
      </div>
    `;

    // -------------------------------------------------------------
    // CARD 2: ПОДВАЛ СТРАНИЦЫ (Footer) - Right Column Row 1
    // -------------------------------------------------------------
    const footerLines = Array.isArray(footer.lines) ? footer.lines : ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"];
    let effectiveFooterLines = [...footerLines];
    if (effectiveFooterLines.includes("footer_rev_ver_date")) {
      effectiveFooterLines = effectiveFooterLines.filter((k) => k !== "footer_rev_ver_date");
      if (!effectiveFooterLines.includes("footer_ver_rev")) effectiveFooterLines.push("footer_ver_rev");
      if (!effectiveFooterLines.includes("footer_articul")) effectiveFooterLines.push("footer_articul");
      if (!effectiveFooterLines.includes("footer_date")) effectiveFooterLines.push("footer_date");
    }

    const defaultFooterAligns = {
      footer_last_edit: "left",
      footer_ver_rev: "center",
      footer_articul: "center",
      footer_date: "center",
      footer_page_total: "right"
    };
    const footerLineAligns = Object.assign({}, defaultFooterAligns, footer.line_aligns || {});

    const footerFontSize = footer.font_size !== undefined ? parseFloat(footer.font_size) : 8.5;
    const isFooterVis = footer.visible !== false;

    const sampleRev = (wf.revision || info.revision || "001").trim();
    const sampleVer = (wf.version || info.version || "01").trim();
    const sampleArt = (info.articul || "CF#...").trim();
    const sampleDate = (wf.last_edit_date || info.date || new Date().toLocaleDateString()).trim();
    const sampleLastEdit = (wf.last_edit || "Корректировка фасадов").trim();

    const footerItemsDef = [
      {
        key: "footer_last_edit",
        label: "Последние изменения",
        icon: "📝",
        preview: sampleLastEdit
      },
      {
        key: "footer_ver_rev",
        label: "Версия # Ревизия",
        icon: "🔢",
        preview: `v.${sampleVer} # rev.${sampleRev}`
      },
      {
        key: "footer_articul",
        label: "Артикул",
        icon: "🔖",
        preview: sampleArt
      },
      {
        key: "footer_date",
        label: "Дата",
        icon: "🗓️",
        preview: sampleDate
      },
      {
        key: "footer_page_total",
        label: "Страница Страниц",
        icon: "📄",
        preview: "1 | 4"
      }
    ];

    const cardFooterHtml = `
      <div class="tpl-card tpl-panel-left ${!isFooterVis ? 'disabled-card disabled-block' : ''}" id="card_footer">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">📌</span>
            <span class="tpl-card-title">Подвал страницы (Footer)</span>
          </div>
          <div class="tpl-card-header-actions">
            <div class="tpl-footer-font-control">
              <span class="tpl-footer-font-label">Шрифт подвала:</span>
              <select id="sel_footer_fontsize" class="form-control tpl-control-select">
                ${renderFontSizeOptions(footerFontSize, BLOCK_FONT_SIZES, 8)}
              </select>
            </div>
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin-left: 4px;">
              <input type="checkbox" id="chk_footer_visible" ${isFooterVis ? 'checked' : ''}>
              <span>Вкл</span>
            </label>
          </div>
        </div>
        <div class="tpl-card-body">
          <div>
            <div class="tpl-ftr-columns-header" style="display: flex; justify-content: space-between; align-items: center; font-size: 11px; font-weight: 700; color: #475569; margin-bottom: 6px; padding: 0 4px;">
              <span>Выводимые секции подвала:</span>
              <span style="font-size: 10.5px; color: #64748b; font-weight: 600;">Выравнивание: слева / центр / справа</span>
            </div>
            <div class="tpl-lines-checklist">
              ${footerItemsDef.map((item) => {
                const isChecked = effectiveFooterLines.includes(item.key);
                const curAlign = footerLineAligns[item.key] || defaultFooterAligns[item.key] || "center";
                return `
                  <div class="tpl-line-item tpl-ftr-line-row">
                    <label class="tpl-ftr-label-wrap">
                      <input type="checkbox" class="chk-ftr-line" data-key="${item.key}" ${isChecked ? 'checked' : ''}>
                      <span class="tpl-line-label">${item.icon} ${item.label}</span>
                      <span class="tpl-line-preview">(${item.preview})</span>
                    </label>
                    <div class="tpl-ftr-align-picker">
                      <div class="tpl-btn-group tpl-ftr-align-group" data-key="${item.key}">
                        <button type="button" class="tpl-btn-align tpl-btn-ftr-align ${curAlign === 'left' ? 'active' : ''}" data-key="${item.key}" data-align="left" title="Слева">Слева</button>
                        <button type="button" class="tpl-btn-align tpl-btn-ftr-align ${curAlign === 'center' ? 'active' : ''}" data-key="${item.key}" data-align="center" title="По центру">Центр</button>
                        <button type="button" class="tpl-btn-align tpl-btn-ftr-align ${curAlign === 'right' ? 'active' : ''}" data-key="${item.key}" data-align="right" title="Справа">Справа</button>
                      </div>
                    </div>
                  </div>
                `;
              }).join("")}
            </div>
          </div>
        </div>
      </div>
    `;

    // -------------------------------------------------------------
    // FULL TWO-COLUMN ASSEMBLY + TOP & BOTTOM CONTROLS
    // -------------------------------------------------------------
    const isImageVis = image43.visible !== false;

    html += `
      <!-- TOP CONTROL: Column width from edge (% от края листа) -->
      <div class="tpl-card tpl-toolbar-card">
        <div class="tpl-card-body" style="padding: 10px 14px; display: flex; flex-direction: column; gap: 8px;">
          <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;">
            
            <!-- LEFT COLUMN WIDTH (% FROM LEFT EDGE) -->
            <div style="display: flex; align-items: center; gap: 8px;">
              <span class="tpl-control-label" style="font-size: 11.5px; font-weight: 700; color: #1e293b;">⬅️ Левая колонка (% от левого края):</span>
              <input type="number" id="inp_col_width_left" class="form-control tpl-control-input" min="10" max="80" step="1" value="${colWidthLeft}" style="width: 56px; font-weight: 700;">
              <span style="font-size: 11.5px; font-weight: 600; color: #64748b;">%</span>
              <input type="range" id="rng_col_width_left" min="10" max="70" step="1" value="${colWidthLeft}" style="width: 80px; cursor: pointer; accent-color: #005eb0;">
            </div>

            <!-- QUICK PRESETS -->
            <div style="display: flex; align-items: center; gap: 4px;">
              <span style="font-size: 10.5px; color: #64748b; font-weight: 600; margin-right: 2px;">Пресеты:</span>
              <button type="button" class="btn btn-xs btn-secondary btn-col-preset" data-w="25" title="25% от каждого края">25%</button>
              <button type="button" class="btn btn-xs btn-secondary btn-col-preset" data-w="30" title="30% от каждого края">30%</button>
              <button type="button" class="btn btn-xs btn-secondary btn-col-preset" data-w="35" title="35% от каждого края">35%</button>
              <button type="button" class="btn btn-xs btn-secondary btn-col-preset" data-w="40" title="40% от каждого края">40%</button>
              <button type="button" class="btn btn-xs btn-secondary btn-col-preset" data-w="50" title="50% от края (встык по центру)">50% (встык)</button>
            </div>

            <!-- RIGHT COLUMN WIDTH (% FROM RIGHT EDGE) -->
            <div style="display: flex; align-items: center; gap: 8px;">
              <input type="range" id="rng_col_width_right" min="10" max="70" step="1" value="${colWidthRight}" style="width: 80px; cursor: pointer; accent-color: #005eb0;">
              <input type="number" id="inp_col_width_right" class="form-control tpl-control-input" min="10" max="80" step="1" value="${colWidthRight}" style="width: 56px; font-weight: 700;">
              <span style="font-size: 11.5px; font-weight: 600; color: #64748b;">%</span>
              <span class="tpl-control-label" style="font-size: 11.5px; font-weight: 700; color: #1e293b;">:Правая колонка (% от правого края) ➡️</span>
            </div>

          </div>

          <div style="display: flex; justify-content: space-between; align-items: center; border-top: 1px dashed var(--border-light); padding-top: 6px; font-size: 11px; color: #64748b;">
            <label class="checkbox-label" style="font-size: 11px; font-weight: 600; cursor: pointer;">
              <input type="checkbox" id="chk_sync_col_width" ${colWidthLeft === colWidthRight ? 'checked' : ''}>
              <span>🔗 Одинаковая ширина (синхронизировать от левого и правого краев)</span>
            </label>
            <div>
              Текст на странице PDF: левые блоки <b>слева</b>, правые <b>справа</b>, нижние — <b>автоматически от низа</b>
            </div>
          </div>
        </div>
      </div>

      <!-- TWO-COLUMNS MAIN GRID -->
      <div class="tpl-two-columns-layout">
        <!-- ROW 1: Header (Left) and Footer (Right) on the same level -->
        ${cardHeaderHtml}
        ${cardFooterHtml}

        <!-- ROW 2: Slot 1 (Left Top) and Slot 3 (Right Top) on the same level -->
        ${renderSlotCardHtml("slot_1", "Левый верхний блок (Слот 1)", "📑", "left", slot1, true, colWidthLeft, info, wf)}
        ${renderSlotCardHtml("slot_3", "Правый верхний блок (Слот 3)", "📑", "right", slot3, true, colWidthRight, info, wf)}

        <!-- ROW 3: Slot 2 (Left Bottom) and Slot 4 (Right Bottom) on the same level -->
        ${renderSlotCardHtml("slot_2", "Левый нижний блок (Слот 2)", "📑", "left", slot2, false, colWidthLeft, info, wf)}
        ${renderSlotCardHtml("slot_4", "Правый нижний блок (Слот 4)", "📑", "right", slot4, false, colWidthRight, info, wf)}
      </div>

      <!-- BOTTOM: 3D IMAGE & SHEET SETTINGS -->
      <div class="tpl-card">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">🖼️</span>
            <span class="tpl-card-title">Фоновое 3D изображение и параметры листа</span>
          </div>
        </div>
        <div class="tpl-card-body">
          <div class="tpl-controls-row">
            <label class="checkbox-label" style="font-size: 11.5px; font-weight: 700; cursor: pointer;">
              <input type="checkbox" id="chk_image_4_3_visible" ${isImageVis ? 'checked' : ''}>
              <span>Отображать фоновый 3D чертеж сцены (пропорции 4:3) под текстом</span>
            </label>
          </div>
          <p style="font-size: 11px; color: #64748b; margin: 0; line-height: 1.4;">
            Рендер видового экрана SketchUp выводится на заднем плане под всеми информационными блоками листа без обрезки полей.
          </p>
        </div>
      </div>
    `;

    els.templateSettingsContainer.innerHTML = html;
    bindTemplateSettingsEvents(tplKey);
  }

  function renderSlotCardHtml(slotId, title, icon, side, slotData, isFullList, widthPct, info, wf) {
    const isVis = slotData.visible !== false;
    const fontSize = slotData.font_size !== undefined ? parseFloat(slotData.font_size) : 8;
    const lines = Array.isArray(slotData.lines) ? slotData.lines : (DEFAULT_LINES_BY_CONTENT[slotData.content] || DEFAULT_LINES_BY_CONTENT[slotId] || []);

    const fullAvailableLines = [
      { key: "toc_pages",         label: "📑 Содержание (список страниц)", val: "1. Титул, 2. План" },
      { key: "spec_materials",    label: "🛠️ Материалы и Фурнитура",      val: "МДФ, Blum, эмаль" },
      { key: "spec_appliances",   label: "🔌 Техника и подсветка",        val: "LED 4000K, Вытяжка" },
      { key: "general_notes",     label: "📝 Общие пояснения",            val: "Замеры выполнены" },
      { key: "workflow_history",  label: "📜 История правок",             val: (wf.last_edit || "Корректировка фасадов").trim() },
      { key: "workflow_stadia",   label: "⏱️ Стадия проекта",             val: (info.stadia || "РД").trim() },
      { key: "workflow_revision", label: "🔢 Ревизия",                   val: (wf.revision || "001").trim() },
      { key: "workflow_version",  label: "🏷️ Версия",                    val: (wf.version || "01").trim() },
      { key: "workflow_date",     label: "📅 Дата",                      val: (wf.date_order || new Date().toISOString().slice(0, 10)).trim() },
      { key: "articul",           label: "🔖 Артикул проекта",           val: (info.articul || "CF#...").trim() }
    ];

    const availableList = isFullList ? fullAvailableLines : fullAvailableLines.filter(l => ["workflow_history", "workflow_stadia", "articul", "workflow_date"].includes(l.key));

    const isRight = side === "right";
    const panelCls = isRight ? "tpl-panel-right" : "tpl-panel-left";
    const textAlign = isRight ? "right" : "left";

    // Controls for Left / Right slot
    const widthControlHtml = (slotId === "slot_1" || slotId === "slot_3")
      ? (isRight
          ? `<div class="tpl-control-item" title="Ширина блока в % от правого края листа"><span style="font-size: 10.5px; color: #64748b;">% от края</span><input type="number" class="form-control tpl-control-input inp-slot-col-w" data-side="right" min="10" max="80" step="1" value="${widthPct}" style="width: 46px; height: 24px; font-weight: 700;"><span class="tpl-control-label">:Ширина</span></div>`
          : `<div class="tpl-control-item" title="Ширина блока в % от левого края листа"><span class="tpl-control-label">Ширина:</span><input type="number" class="form-control tpl-control-input inp-slot-col-w" data-side="left" min="10" max="80" step="1" value="${widthPct}" style="width: 46px; height: 24px; font-weight: 700;"><span style="font-size: 10.5px; color: #64748b;">% от края</span></div>`)
      : "";

    const isBottomSlot = (slotId === "slot_2" || slotId === "slot_4");
    const alignBadgeHtml = isRight
      ? `<span class="badge" style="font-size: 9.5px; background: #f1f5f9; color: #334155; padding: 2px 6px; border-radius: 3px; font-weight: 600;" title="Текст на странице PDF выравнивается ${isBottomSlot ? 'от низа и ' : ''}по правому краю">${isBottomSlot ? 'От низа ⬇ • ' : ''}Текст справа ➡</span>`
      : `<span class="badge" style="font-size: 9.5px; background: #e0f2fe; color: #0369a1; padding: 2px 6px; border-radius: 3px; font-weight: 600;" title="Текст на странице PDF выравнивается ${isBottomSlot ? 'от низа и ' : ''}по левому краю">⬅ Текст слева${isBottomSlot ? ' • От низа ⬇' : ''}</span>`;

    return `
      <div class="tpl-card ${panelCls} ${!isVis ? 'disabled-card disabled-block' : ''}" id="block_${slotId}">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">${icon || '📋'}</span>
            <span class="tpl-card-title">${title}</span>
          </div>
          <div class="tpl-card-header-actions">
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer;">
              <input type="checkbox" class="chk-slot-visible" data-slot="${slotId}" ${isVis ? 'checked' : ''}>
              <span>Вкл</span>
            </label>
          </div>
        </div>

        <div class="tpl-card-body">
          <div class="tpl-controls-row">
            ${!isRight ? `
              <div class="tpl-control-item">
                <span class="tpl-control-label">Шрифт:</span>
                <select class="form-control tpl-control-select sel-slot-fontsize" data-slot="${slotId}">
                  ${renderFontSizeOptions(fontSize, BLOCK_FONT_SIZES, 8)}
                </select>
              </div>
              ${widthControlHtml}
              ${alignBadgeHtml}
              <div style="margin-left: auto; display: flex; gap: 4px;">
                <button type="button" class="btn btn-xs btn-secondary btn-slot-all" data-slot="${slotId}" style="font-size: 9.5px; padding: 1px 6px;">Все</button>
                <button type="button" class="btn btn-xs btn-secondary btn-slot-none" data-slot="${slotId}" style="font-size: 9.5px; padding: 1px 6px;">Снять</button>
              </div>
            ` : `
              <div style="margin-right: auto; display: flex; gap: 4px;">
                <button type="button" class="btn btn-xs btn-secondary btn-slot-all" data-slot="${slotId}" style="font-size: 9.5px; padding: 1px 6px;">Все</button>
                <button type="button" class="btn btn-xs btn-secondary btn-slot-none" data-slot="${slotId}" style="font-size: 9.5px; padding: 1px 6px;">Снять</button>
              </div>
              ${alignBadgeHtml}
              ${widthControlHtml}
              <div class="tpl-control-item">
                <span class="tpl-control-label">Шрифт:</span>
                <select class="form-control tpl-control-select sel-slot-fontsize" data-slot="${slotId}">
                  ${renderFontSizeOptions(fontSize, BLOCK_FONT_SIZES, 8)}
                </select>
              </div>
            `}
          </div>

          <div>
            <div style="font-size: 11px; font-weight: 700; color: #475569; margin-bottom: 6px; text-align: ${textAlign};">Выводимые строки блока:</div>
            <div class="tpl-lines-checklist">
              ${availableList.map(item => `
                <label class="tpl-line-item">
                  <input type="checkbox" class="chk-slot-line" data-slot="${slotId}" data-key="${item.key}" ${lines.includes(item.key) ? 'checked' : ''}>
                  <span class="tpl-line-label">${item.label}</span>
                  ${item.val ? `<span class="tpl-line-preview">(${item.val})</span>` : ''}
                </label>
              `).join("")}
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function bindTemplateSettingsEvents(tplKey) {
    if (!els.templateSettingsContainer) return;

    // Helper to notify and auto-save layout if bridge exists
    const notifyChange = () => {
      markDirty();
      if (window.bridge && typeof bridge.saveLayout === "function") {
        bridge.saveLayout(JSON.stringify(state.pdf_settings.custom_layouts));
      }
    };

    // Header Visible Toggle
    const chkHdrVis = document.getElementById("chk_header_visible");
    if (chkHdrVis) {
      chkHdrVis.addEventListener("change", (e) => {
        updateBlockSlot("header", { visible: e.target.checked });
        const card = document.getElementById("card_header");
        if (card) card.classList.toggle("disabled-card", !e.target.checked);
        notifyChange();
      });
    }



    // Header Valign Buttons
    const grpHdrValign = document.getElementById("grp_header_valign");
    if (grpHdrValign) {
      const btns = grpHdrValign.querySelectorAll(".tpl-btn-align");
      btns.forEach((btn) => {
        btn.addEventListener("click", () => {
          btns.forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          updateBlockSlot("header", { valign: btn.dataset.valign, align: "center" });
          notifyChange();
        });
      });
    }

    // Header Lines Checkboxes
    const hdrCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-hdr-line");
    hdrCheckboxes.forEach((chk) => {
      chk.addEventListener("change", () => {
        const checkedKeys = Array.from(hdrCheckboxes)
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        updateBlockSlot("header", { lines: checkedKeys });
        notifyChange();
      });
    });

    // Header Line Row Selection (Dropdown)
    const hdrRowSelects = els.templateSettingsContainer.querySelectorAll(".sel-hdr-line-row");
    hdrRowSelects.forEach((sel) => {
      sel.addEventListener("change", () => {
        const key = sel.dataset.key;
        const row = parseInt(sel.value, 10);
        if (!key || isNaN(row)) return;

        const curHeader = getBlockData("header") || {};
        const currentLineRows = Object.assign({}, curHeader.line_rows || {
          furniture_name: 1,
          place_address: 2,
          customer_or_company: 3,
          scene_name: 4,
          scene_description: 5
        });
        currentLineRows[key] = row;

        const chk = els.templateSettingsContainer.querySelector(`.chk-hdr-line[data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const checkedKeys = Array.from(hdrCheckboxes)
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("header", { lines: checkedKeys, line_rows: currentLineRows });
        } else {
          updateBlockSlot("header", { line_rows: currentLineRows });
        }
        notifyChange();
      });
    });

    // Header Line Font Size Selection (Dropdown)
    const hdrSizeSelects = els.templateSettingsContainer.querySelectorAll(".sel-hdr-line-size");
    hdrSizeSelects.forEach((sel) => {
      sel.addEventListener("change", () => {
        const key = sel.dataset.key;
        const sz = parseFloat(sel.value);
        if (!key || isNaN(sz)) return;

        const curHeader = getBlockData("header") || {};
        const currentLineSizes = Object.assign({}, curHeader.line_font_sizes || {
          furniture_name: 11,
          place_address: 10,
          customer_or_company: 10,
          scene_name: 11,
          scene_description: 9
        });
        currentLineSizes[key] = sz;

        const chk = els.templateSettingsContainer.querySelector(`.chk-hdr-line[data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const checkedKeys = Array.from(hdrCheckboxes)
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("header", { lines: checkedKeys, line_font_sizes: currentLineSizes });
        } else {
          updateBlockSlot("header", { line_font_sizes: currentLineSizes });
        }
        notifyChange();
      });
    });

    // Header Line Color Picker (Square <input type="color">)
    const hdrColorInputs = els.templateSettingsContainer.querySelectorAll(".inp-hdr-line-color");
    hdrColorInputs.forEach((inp) => {
      const handleColorChange = () => {
        const key = inp.dataset.key;
        const col = inp.value;
        if (!key || !col) return;

        const curHeader = getBlockData("header") || {};
        const currentLineColors = Object.assign({}, curHeader.line_colors || {
          furniture_name: "#005EB0",
          place_address: "#0F172A",
          customer_or_company: "#0F172A",
          scene_name: "#005EB0",
          scene_description: "#475569"
        });
        currentLineColors[key] = col;

        const chk = els.templateSettingsContainer.querySelector(`.chk-hdr-line[data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const checkedKeys = Array.from(hdrCheckboxes)
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("header", { lines: checkedKeys, line_colors: currentLineColors });
        } else {
          updateBlockSlot("header", { line_colors: currentLineColors });
        }
        notifyChange();
      };
      inp.addEventListener("input", handleColorChange);
      inp.addEventListener("change", handleColorChange);
    });

    // Header Line Row Selection (Buttons fallback)
    const hdrRowBtns = els.templateSettingsContainer.querySelectorAll(".tpl-btn-hdr-row");
    hdrRowBtns.forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        e.preventDefault();
        const key = btn.dataset.key;
        const row = parseInt(btn.dataset.row, 10);
        if (!key || isNaN(row)) return;

        const group = btn.closest(".tpl-hdr-row-group");
        if (group) {
          group.querySelectorAll(".tpl-btn-hdr-row").forEach((b) => b.classList.remove("active"));
        }
        btn.classList.add("active");

        const curHeader = getBlockData("header") || {};
        const currentLineRows = Object.assign({}, curHeader.line_rows || {
          furniture_name: 1,
          place_address: 2,
          customer_or_company: 3,
          scene_name: 4,
          scene_description: 5
        });
        currentLineRows[key] = row;

        const chk = els.templateSettingsContainer.querySelector(`.chk-hdr-line[data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const checkedKeys = Array.from(hdrCheckboxes)
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("header", { lines: checkedKeys, line_rows: currentLineRows });
        } else {
          updateBlockSlot("header", { line_rows: currentLineRows });
        }
        notifyChange();
      });
    });

    // Column Width (% from edge) Inputs, Sliders, and Presets
    const syncColInputs = (side, val) => {
      val = Math.round(val * 10) / 10;
      if (side === "left" || side === "all") {
        const inp = document.getElementById("inp_col_width_left");
        if (inp && parseFloat(inp.value) !== val) inp.value = val;
        const rng = document.getElementById("rng_col_width_left");
        if (rng && parseFloat(rng.value) !== val) rng.value = val;
        const cardInp = els.templateSettingsContainer.querySelector('.inp-slot-col-w[data-side="left"]');
        if (cardInp && parseFloat(cardInp.value) !== val) cardInp.value = val;
      }
      if (side === "right" || side === "all") {
        const inp = document.getElementById("inp_col_width_right");
        if (inp && parseFloat(inp.value) !== val) inp.value = val;
        const rng = document.getElementById("rng_col_width_right");
        if (rng && parseFloat(rng.value) !== val) rng.value = val;
        const cardInp = els.templateSettingsContainer.querySelector('.inp-slot-col-w[data-side="right"]');
        if (cardInp && parseFloat(cardInp.value) !== val) cardInp.value = val;
      }
    };

    const handleColWidthChange = (side, val) => {
      val = Math.max(10, Math.min(80, Math.round(parseFloat(val) * 10) / 10));
      if (isNaN(val)) return;

      updateColumnWidthFromEdge(side, val);
      syncColInputs(side, val);

      const chkSync = document.getElementById("chk_sync_col_width");
      if (chkSync && chkSync.checked) {
        const otherSide = side === "left" ? "right" : "left";
        updateColumnWidthFromEdge(otherSide, val);
        syncColInputs(otherSide, val);
      }
      notifyChange();
    };

    // Left Column Inputs
    const inpColLeft = document.getElementById("inp_col_width_left");
    if (inpColLeft) {
      inpColLeft.addEventListener("input", (e) => handleColWidthChange("left", e.target.value));
      inpColLeft.addEventListener("change", (e) => handleColWidthChange("left", e.target.value));
    }
    const rngColLeft = document.getElementById("rng_col_width_left");
    if (rngColLeft) {
      rngColLeft.addEventListener("input", (e) => handleColWidthChange("left", e.target.value));
      rngColLeft.addEventListener("change", (e) => handleColWidthChange("left", e.target.value));
    }

    // Right Column Inputs
    const inpColRight = document.getElementById("inp_col_width_right");
    if (inpColRight) {
      inpColRight.addEventListener("input", (e) => handleColWidthChange("right", e.target.value));
      inpColRight.addEventListener("change", (e) => handleColWidthChange("right", e.target.value));
    }
    const rngColRight = document.getElementById("rng_col_width_right");
    if (rngColRight) {
      rngColRight.addEventListener("input", (e) => handleColWidthChange("right", e.target.value));
      rngColRight.addEventListener("change", (e) => handleColWidthChange("right", e.target.value));
    }

    // Preset Buttons
    const presetBtns = els.templateSettingsContainer.querySelectorAll(".btn-col-preset");
    presetBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        const w = parseFloat(btn.dataset.w);
        if (!isNaN(w)) {
          updateColumnWidthFromEdge("left", w);
          updateColumnWidthFromEdge("right", w);
          syncColInputs("all", w);
          notifyChange();
        }
      });
    });

    // In-Card Column Width Inputs
    const cardColInputs = els.templateSettingsContainer.querySelectorAll(".inp-slot-col-w");
    cardColInputs.forEach((inp) => {
      inp.addEventListener("input", (e) => handleColWidthChange(e.target.dataset.side, e.target.value));
      inp.addEventListener("change", (e) => handleColWidthChange(e.target.dataset.side, e.target.value));
    });

    // Slot Visibility Toggles
    const slotVisCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-slot-visible");
    slotVisCheckboxes.forEach((chk) => {
      chk.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot;
        updateBlockSlot(sId, { visible: e.target.checked });
        const blk = document.getElementById(`block_${sId}`);
        if (blk) {
          blk.classList.toggle("disabled-block", !e.target.checked);
          blk.classList.toggle("disabled-card", !e.target.checked);
        }
        notifyChange();
      });
    });

    // Slot Font Size Selects
    const slotFsSelects = els.templateSettingsContainer.querySelectorAll(".sel-slot-fontsize");
    slotFsSelects.forEach((sel) => {
      sel.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot;
        updateBlockSlot(sId, { font_size: parseFloat(e.target.value) });
        notifyChange();
      });
    });

    // Slot Lines Checkboxes
    const slotLineCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-slot-line");
    slotLineCheckboxes.forEach((chk) => {
      chk.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot;
        const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll(`.chk-slot-line[data-slot="${sId}"]`))
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        updateBlockSlot(sId, { lines: allSlotLines });
        notifyChange();
      });
    });

    // Slot Quick Actions (Все / Снять)
    const btnSlotAll = els.templateSettingsContainer.querySelectorAll(".btn-slot-all");
    btnSlotAll.forEach((btn) => {
      btn.addEventListener("click", () => {
        const sId = btn.dataset.slot;
        const checks = els.templateSettingsContainer.querySelectorAll(`.chk-slot-line[data-slot="${sId}"]`);
        const keys = [];
        checks.forEach((c) => {
          c.checked = true;
          keys.push(c.dataset.key);
        });
        updateBlockSlot(sId, { lines: keys });
        notifyChange();
      });
    });

    const btnSlotNone = els.templateSettingsContainer.querySelectorAll(".btn-slot-none");
    btnSlotNone.forEach((btn) => {
      btn.addEventListener("click", () => {
        const sId = btn.dataset.slot;
        const checks = els.templateSettingsContainer.querySelectorAll(`.chk-slot-line[data-slot="${sId}"]`);
        checks.forEach((c) => (c.checked = false));
        updateBlockSlot(sId, { lines: [] });
        notifyChange();
      });
    });

    // Footer Visible Toggle
    const chkFtrVis = document.getElementById("chk_footer_visible");
    if (chkFtrVis) {
      chkFtrVis.addEventListener("change", (e) => {
        updateBlockSlot("footer", { visible: e.target.checked });
        const card = document.getElementById("card_footer");
        if (card) card.classList.toggle("disabled-card", !e.target.checked);
        notifyChange();
      });
    }

    // Footer Font Size
    const selFtrFs = document.getElementById("sel_footer_fontsize");
    if (selFtrFs) {
      selFtrFs.addEventListener("change", (e) => {
        updateBlockSlot("footer", { font_size: parseFloat(e.target.value) });
        notifyChange();
      });
    }

    // Footer Lines Checkboxes
    const ftrCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-ftr-line");
    ftrCheckboxes.forEach((chk) => {
      chk.addEventListener("change", () => {
        const checkedKeys = Array.from(ftrCheckboxes)
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        updateBlockSlot("footer", { lines: checkedKeys });
        notifyChange();
      });
    });

    // Footer Line Alignment Buttons
    const ftrAlignBtns = els.templateSettingsContainer.querySelectorAll(".tpl-btn-ftr-align");
    ftrAlignBtns.forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const key = btn.dataset.key;
        const align = btn.dataset.align;
        if (!key || !align) return;

        const group = btn.closest(".tpl-ftr-align-group");
        if (group) {
          group.querySelectorAll(".tpl-btn-ftr-align").forEach((b) => b.classList.remove("active"));
        }
        btn.classList.add("active");

        const curFooter = getBlockData("footer") || {};
        const defaultFooterAligns = {
          footer_last_edit: "left",
          footer_ver_rev: "center",
          footer_articul: "center",
          footer_date: "center",
          footer_page_total: "right"
        };
        const currentLineAligns = Object.assign({}, defaultFooterAligns, curFooter.line_aligns || {});
        currentLineAligns[key] = align;

        const chk = els.templateSettingsContainer.querySelector(`.chk-ftr-line[data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const checkedKeys = Array.from(ftrCheckboxes)
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("footer", { lines: checkedKeys, line_aligns: currentLineAligns });
        } else {
          updateBlockSlot("footer", { line_aligns: currentLineAligns });
        }
        notifyChange();
      });
    });

    // Image 4:3 Toggle
    const chkImgVis = document.getElementById("chk_image_4_3_visible");
    if (chkImgVis) {
      chkImgVis.addEventListener("change", (e) => {
        updateBlockSlot("image_4_3", { visible: e.target.checked });
        notifyChange();
      });
    }
  }

  // Alias for backward compatibility with existing render calls
  function renderLayoutCanvas() {
    renderTemplateSettingsList();
  }

  // Layout & Template Settings Setup
  function setupLayoutEditor() {
    // Template switcher
    if (els.selectLayoutTemplate) {
      els.selectLayoutTemplate.addEventListener("change", (e) => {
        layoutState.currentTemplate = e.target.value;
        renderTemplateSettingsList();
        updateLayoutUsageBadge();
      });
    }

    // Margin input
    if (els.inputLayoutMargin) {
      els.inputLayoutMargin.addEventListener("change", (e) => {
        const val = parseFloat(e.target.value) || 0;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.margin_mm = val;
        markDirty();
        if (window.bridge && typeof bridge.saveSettings === "function") {
          bridge.saveSettings(JSON.stringify(state.pdf_settings));
        }
      });
    }

    // Reset Layout Button
    if (els.btnResetLayout) {
      els.btnResetLayout.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        const defTpl = DEFAULT_LAYOUTS[tplKey];
        if (!defTpl) return;

        if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
        state.pdf_settings.custom_layouts[tplKey] = {};

        const tplDefaults = defTpl.slots || {};
        FIXED_SLOT_DEFS.forEach((slotDef) => {
          const defSlot = tplDefaults[slotDef.id] || {};
          const defContent = defSlot.content || slotDef.default_content || "none";
          const defFontSize = defSlot.font_size !== undefined ? defSlot.font_size : (slotDef.id === "header" ? 11 : (slotDef.id === "footer" ? 8.5 : 8));
          const defLines = defSlot.lines ? [...defSlot.lines] : [...(DEFAULT_LINES_BY_CONTENT[slotDef.id] || DEFAULT_LINES_BY_CONTENT[defContent] || [])];
          const defLineRows = defSlot.line_rows ? Object.assign({}, defSlot.line_rows) : (slotDef.default_line_rows ? Object.assign({}, slotDef.default_line_rows) : null);
          const defLineFontSizes = defSlot.line_font_sizes ? Object.assign({}, defSlot.line_font_sizes) : (slotDef.default_line_font_sizes ? Object.assign({}, slotDef.default_line_font_sizes) : null);
          const defLineColors = defSlot.line_colors ? Object.assign({}, defSlot.line_colors) : (slotDef.default_line_colors ? Object.assign({}, slotDef.default_line_colors) : null);
          const defLineAligns = defSlot.line_aligns ? Object.assign({}, defSlot.line_aligns) : (slotDef.default_line_aligns ? Object.assign({}, slotDef.default_line_aligns) : null);
          state.pdf_settings.custom_layouts[tplKey][slotDef.id] = {
            visible: defSlot.visible !== false,
            content: defContent,
            custom_text: defSlot.custom_text || "",
            align: defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left"),
            valign: defSlot.valign || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "top"),
            font_size: defFontSize,
            lines: defLines,
            line_rows: defLineRows,
            line_font_sizes: defLineFontSizes,
            line_colors: defLineColors,
            line_aligns: defLineAligns,
            opacity: defSlot.opacity !== undefined ? defSlot.opacity : 0.9,
            x: defSlot.x !== undefined ? defSlot.x : slotDef.x,
            y: defSlot.y !== undefined ? defSlot.y : slotDef.y,
            w: defSlot.w !== undefined ? defSlot.w : slotDef.w,
            h: defSlot.h !== undefined ? defSlot.h : slotDef.h
          };
        });

        renderTemplateSettingsList();
        showNotification(`Настройки шаблона «${defTpl.name}» сброшены к стандартам`, "success");
        if (window.bridge && typeof bridge.saveLayout === "function") {
          bridge.saveLayout(JSON.stringify(state.pdf_settings.custom_layouts));
        }
      });
    }

    renderTemplateSettingsList();
  }

  // -----------------------------------------------------------------------------
  // Draggable Split Resizer (Divider between Pages/Scenes and Block Settings)
  // -----------------------------------------------------------------------------
  function setupSplitResizer() {
    const resizer = els.scenesSplitResizer || document.getElementById("scenesSplitResizer");
    const scenesPanel = els.scenesPanel || document.getElementById("scenesPanel");
    const tabScenes = document.getElementById("tab-scenes");
    if (!resizer || !scenesPanel || !tabScenes) return;

    // Restore saved width from localStorage if available
    try {
      const savedWidth = localStorage.getItem("dn1c_scenes_panel_width");
      if (savedWidth) {
        const parsed = parseInt(savedWidth, 10);
        if (!isNaN(parsed) && parsed >= 240 && parsed <= (window.innerWidth - 280)) {
          scenesPanel.style.width = `${parsed}px`;
        }
      }
    } catch (e) {}

    let isDragging = false;
    let startX = 0;
    let startWidth = 0;

    resizer.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return; // only left mouse button
      isDragging = true;
      startX = e.clientX;
      startWidth = scenesPanel.getBoundingClientRect().width;

      resizer.classList.add("is-dragging");
      document.body.classList.add("is-resizing");
      e.preventDefault();
    });

    document.addEventListener("mousemove", (e) => {
      if (!isDragging) return;
      const deltaX = e.clientX - startX;
      const totalWidth = tabScenes.getBoundingClientRect().width || window.innerWidth;
      const minW = 240;
      const maxW = Math.max(minW, totalWidth - 280);
      const newWidth = Math.min(Math.max(startWidth + deltaX, minW), maxW);

      scenesPanel.style.width = `${Math.round(newWidth)}px`;
      e.preventDefault();
    });

    document.addEventListener("mouseup", (e) => {
      if (!isDragging) return;
      isDragging = false;
      resizer.classList.remove("is-dragging");
      document.body.classList.remove("is-resizing");

      try {
        const curW = parseInt(scenesPanel.style.width, 10);
        if (!isNaN(curW)) {
          localStorage.setItem("dn1c_scenes_panel_width", curW.toString());
        }
      } catch (e) {}
    });

    // Double-click to reset width back to default (380px)
    resizer.addEventListener("dblclick", () => {
      scenesPanel.style.width = "380px";
      try {
        localStorage.setItem("dn1c_scenes_panel_width", "380");
      } catch (e) {}
    });
  }

  // -----------------------------------------------------------------------------
  // Universal Wheel Scrolling Fix across All Blocks & Panels
  // -----------------------------------------------------------------------------
  function setupScrollWheelHandlers() {
    const tplScroll = els.templateSettingsContainer || document.getElementById("templateSettingsContainer");
    const tplPanel = els.templateSettingsPanel || document.getElementById("templateSettingsPanel");

    if (tplPanel && tplScroll) {
      // Forward wheel scrolling from toolbar, header, or anywhere in panel to the scroll container
      tplPanel.addEventListener("wheel", (e) => {
        if (!e.deltaY) return;
        // If cursor is on the toolbar or outside the scroll container, forward scroll to container
        if (e.target && (e.target.closest(".template-settings-toolbar") || e.target.closest(".toolbar-group") || !e.target.closest(".template-settings-scroll"))) {
          tplScroll.scrollTop += e.deltaY;
        }
      }, { passive: true });
    }

    const scenesPanel = els.scenesPanel || document.getElementById("scenesPanel");
    const scenesTableContainer = scenesPanel ? scenesPanel.querySelector(".table-container") : null;
    if (scenesPanel && scenesTableContainer) {
      scenesPanel.addEventListener("wheel", (e) => {
        if (!e.deltaY) return;
        // If cursor is on the scenes toolbar or outside the table container, forward scroll to table
        if (e.target && !e.target.closest(".table-container")) {
          scenesTableContainer.scrollTop += e.deltaY;
        }
      }, { passive: true });
    }

    // Prevent number inputs from stealing wheel event and blocking page scroll
    document.addEventListener("wheel", (e) => {
      if (e.target && e.target.tagName === "INPUT" && e.target.type === "number") {
        e.target.blur();
      }
    }, { passive: true });
  }
  // Data Population & Form Handling
  // -----------------------------------------------------------------------------

  function updateCompanyVisibility() {
    if (!els.companyFieldGroup) return;
    const isCommercial = els.selectTrade && els.selectTrade.value === "1";
    els.companyFieldGroup.style.display = isCommercial ? "flex" : "none";
  }

  function generateArticulLocal(isCommercial, index = 1) {
    const prefix = isCommercial ? "CF#" : "HF#";
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const hh = String(now.getHours()).padStart(2, '0');
    const mi = String(now.getMinutes()).padStart(2, '0');
    const ss = String(now.getSeconds()).padStart(2, '0');
    const idx = String(index || 1).padStart(2, '0');
    return `${prefix}${yy}${mm}${dd}_${hh}${mi}${ss}_${idx}`;
  }

  function generateCustomerIdLocal() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const hh = String(now.getHours()).padStart(2, '0');
    const mi = String(now.getMinutes()).padStart(2, '0');
    const ss = String(now.getSeconds()).padStart(2, '0');
    return `CUST-${yy}${mm}${dd}-${hh}${mi}${ss}`;
  }

  // Populate UI from State
  function renderUI() {
    const prj = state.project || {};
    const cust = state.customer || {};
    const wf = state.workflow || {};
    const info = state.project_info || {};
    const settings = state.pdf_settings || {};

    // Синхронизация истории правок workflow.history_edit <-> state.history
    if (Array.isArray(wf.history_edit) && wf.history_edit.length > 0) {
      state.history = wf.history_edit.map((item) => {
        if (Array.isArray(item)) {
          return { date: item[0] || "", text: item[1] || "", description: item[1] || "" };
        } else if (item && typeof item === "object") {
          return { date: item.date || "", text: item.text || item.description || "", description: item.text || item.description || "" };
        }
        return { date: "", text: String(item || ""), description: String(item || "") };
      });
    } else if (Array.isArray(state.history) && state.history.length > 0) {
      if (!wf.history_edit) {
        wf.history_edit = state.history.map((item) => [item.date || "", item.text || item.description || ""]);
      }
    }

    // 1. Паспорт объекта (Project)
    const isCommercial = prj.commercial !== undefined
      ? Boolean(prj.commercial)
      : (info.trade === 1 || info.trade === "1" || (prj.articul || info.articul || "").startsWith("CF#"));

    if (els.selectTrade) {
      els.selectTrade.value = isCommercial ? "1" : "0";
    }
    updateCompanyVisibility();

    if (els.inputArticul) els.inputArticul.value = prj.articul || info.articul || "";
    if (els.inputCompany) els.inputCompany.value = prj.name_company || info.company || "";
    if (els.inputTags) {
      const tagsVal = prj.tags !== undefined ? prj.tags : (info.tags || "");
      els.inputTags.value = Array.isArray(tagsVal) ? tagsVal.join(", ") : String(tagsVal || "");
    }
    if (els.inputFurnitureName) els.inputFurnitureName.value = prj.product || info.name_product || info.furniture_name || "";
    if (els.inputRoomName) els.inputRoomName.value = prj.place || info.name_place || info.room_name || "";
    if (els.inputAddress) els.inputAddress.value = prj.adress || info.adress || info.address || "";
    if (els.inputProjectDescription) els.inputProjectDescription.value = prj.description || info.description || info.task_description || "";

    // 2. Карточка заказчика (Customer)
    if (els.inputCustomerId) els.inputCustomerId.value = cust.id || cust.customer_id || "";
    if (els.inputCustomer) els.inputCustomer.value = cust.name || info.customer || info.name_customer || "";
    if (els.inputPhone) els.inputPhone.value = cust.phone || info.phone || "";
    if (els.inputEmail) els.inputEmail.value = cust.email || info.email || "";

    // 3. Ход работы (Workflow)
    if (els.inputAuthor) els.inputAuthor.value = wf.author || info.author || "";
    if (els.inputPrice) els.inputPrice.value = (wf.price !== undefined && wf.price !== null) ? wf.price : (info.price || "");
    if (els.inputStartDate) els.inputStartDate.value = wf.start_date || "";
    if (els.inputEndDate) els.inputEndDate.value = wf.end_date || "";
    if (els.inputTotalDuration) els.inputTotalDuration.value = wf.total_duration || "";
    if (els.inputStatus) els.inputStatus.value = wf.status || info.status || "Предварительный";
    if (els.inputVersion) els.inputVersion.value = wf.version || info.version || 1;
    if (els.inputRevision) els.inputRevision.value = wf.revision || info.revision || 1;
    if (els.inputLastEdit) els.inputLastEdit.value = info.last_edit || info.edit || "";

    // Task Brief (для вкладок ТЗ)
    if (els.inputTaskDescription) els.inputTaskDescription.value = info.task_description || prj.description || "";
    if (els.inputTaskDimensions) els.inputTaskDimensions.value = info.task_dimensions || "";
    if (els.inputTaskWishes) els.inputTaskWishes.value = info.task_wishes || "";

    // Specifications
    if (els.inputMaterials) els.inputMaterials.value = info.materials || "";
    if (els.inputAppliances) els.inputAppliances.value = info.appliances || "";
    if (els.inputLighting) els.inputLighting.value = info.lighting || "";
    if (els.inputNotes) els.inputNotes.value = info.notes || "";

    // PDF Settings
    const engine = settings.export_engine || "prawn";
    if (els.selectExportEngine) els.selectExportEngine.value = engine;
    if (els.selectLayoutRenderMode) els.selectLayoutRenderMode.value = settings.layout_render_mode || "raster";
    if (els.chkSaveLayoutFile) els.chkSaveLayoutFile.checked = settings.save_layout_file !== false;
    updateEngineUI();

    if (els.selectPageSize) els.selectPageSize.value = settings.page_size || "A4";
    if (els.selectPageLayout) els.selectPageLayout.value = settings.page_layout || "landscape";
    const marginMm = settings.margin_mm !== undefined && settings.margin_mm !== null
      ? parseFloat(settings.margin_mm)
      : (settings.margin !== undefined && settings.margin !== null ? Math.round((parseFloat(settings.margin) * 25.4) / 72.0) : 5);
    if (els.inputPageMargin) els.inputPageMargin.value = marginMm;
    if (els.inputLayoutMargin) els.inputLayoutMargin.value = marginMm;
    if (els.selectQuality) els.selectQuality.value = (settings.scale_factor || 2.0).toString();
    if (els.selectStamp) els.selectStamp.value = settings.stamp_type || "draft";
    if (els.inputCustomStamp) els.inputCustomStamp.value = settings.stamp_custom || "НЕ УТВЕРЖДЕН";
    if (els.customStampGroup) els.customStampGroup.style.display = settings.stamp_type === "custom" ? "flex" : "none";

    const pColor = settings.primary_color ? `#${settings.primary_color}` : "#005EB0";
    if (els.inputPrimaryColor) els.inputPrimaryColor.value = pColor;
    if (els.primaryColorHex) els.primaryColorHex.textContent = pColor;

    const sColor = settings.stamp_color ? `#${settings.stamp_color}` : "#D32F2F";
    if (els.inputStampColor) els.inputStampColor.value = sColor;
    if (els.stampColorHex) els.stampColorHex.textContent = sColor;

    if (els.chkAutoOpen) els.chkAutoOpen.checked = settings.auto_open_pdf !== false;
    if (els.chkSaveBackup) els.chkSaveBackup.checked = settings.save_skp_backup !== false;
    if (els.chkAntialias) els.chkAntialias.checked = settings.antialias !== false;

    updateHeaderTitles();
    renderScenesTable();
    renderHistoryTable();
    renderDirectories();
    renderApiTargets();
    renderLayoutCanvas();
    updateLayoutUsageBadge();
  }

  // Helper: Format file size
  function formatFileSize(bytes) {
    if (!bytes || bytes <= 0) return "0 B";
    const k = 1024;
    const sizes = ["B", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
  }

  // Helper: Get icon for document extensions
  function getDocIcon(ext) {
    ext = (ext || "").toUpperCase();
    if (ext === "PDF") return "📑";
    if (ext === "DWG" || ext === "DXF") return "📐";
    if (ext === "SKP") return "🏠";
    if (ext === "DOC" || ext === "DOCX" || ext === "TXT" || ext === "RTF") return "📝";
    if (ext === "XLS" || ext === "XLSX" || ext === "CSV") return "📊";
    return "📄";
  }

  // Scan timeouts tracker for directory previews
  const scanTimeouts = {};

  function clearScanTimeout(index) {
    if (scanTimeouts[index]) {
      clearTimeout(scanTimeouts[index]);
      delete scanTimeouts[index];
    }
  }

  function scheduleScanTimeout(index, path) {
    clearScanTimeout(index);
    scanTimeouts[index] = setTimeout(() => {
      const badge = document.getElementById(`dirFileBadge_${index}`);
      const grid = document.getElementById(`dirPreviewGrid_${index}`);
      if (badge && badge.textContent === "Сканирование...") {
        badge.textContent = "Не ответил";
        badge.className = "badge badge-tag badge-list";
      }
      if (grid && grid.querySelector(".dir-empty-state")) {
        grid.innerHTML = `
          <div class="dir-empty-state" style="grid-column: 1 / -1; color: #b45309;">
            ⏱️ Сканирование заняло слишком много времени. Проверьте правильность пути или нажмите «🔄 Обновить».
          </div>`;
      }
    }, 4500);
  }

  // Render Project Directories (directories from YAML) as full Cards with Previews
  function renderDirectories() {
    if (!els.directoriesCardsContainer) return;
    els.directoriesCardsContainer.innerHTML = "";

    // Нормализация к массиву объектов
    if (state.directories && !Array.isArray(state.directories) && typeof state.directories === "object") {
      state.directories = Object.keys(state.directories).map((k) => {
        const v = state.directories[k] || {};
        return {
          path:        v.path || "",
          title:       v.title || k,
          description: v.description || "",
          display:     v.display || "grid"
        };
      });
    }

    if (!Array.isArray(state.directories)) {
      state.directories = [];
    }

    if (state.directories.length === 0) {
      els.directoriesCardsContainer.innerHTML = `
        <div class="empty-dirs-placeholder">
          <div style="font-size: 32px; margin-bottom: 8px;">📁</div>
          <div style="font-weight: 600; color: var(--text-color); font-size: 14px;">Папки проекта не заданы</div>
          <div style="font-size: 12px; color: var(--text-dim); margin-top: 4px;">Нажмите «+ Добавить папку», чтобы создать раздел спецификаций и привязать рабочие файлы.</div>
        </div>`;
      return;
    }

    state.directories.forEach((d, index) => {
      const card = document.createElement("div");
      card.className = "directory-card";
      card.dataset.index = index;

      // 1. HEADER (Номер, Заголовок, Режим отображения, Удалить)
      const headerDiv = document.createElement("div");
      headerDiv.className = "dir-card-header";

      const headerLeft = document.createElement("div");
      headerLeft.className = "dir-header-left";

      const idxBadge = document.createElement("span");
      idxBadge.className = "dir-idx-badge";
      idxBadge.textContent = `📁 Папка #${index + 1}`;

      const titleInput = document.createElement("input");
      titleInput.type = "text";
      titleInput.className = "form-control dir-title-input";
      titleInput.value = d.title || "";
      titleInput.placeholder = "Заголовок раздела (например: Материалы и фурнитура)...";
      titleInput.addEventListener("input", (e) => {
        d.title = e.target.value;
      });

      headerLeft.appendChild(idxBadge);
      headerLeft.appendChild(titleInput);

      const headerRight = document.createElement("div");
      headerRight.className = "dir-header-right";

      const selDisplay = document.createElement("select");
      selDisplay.className = "table-select";
      selDisplay.style.fontSize = "11.5px";

      const optGrid = document.createElement("option");
      optGrid.value = "grid";
      optGrid.textContent = "grid (сетка)";
      if ((d.display || "grid") === "grid") optGrid.selected = true;

      const optList = document.createElement("option");
      optList.value = "list";
      optList.textContent = "list (список)";
      if (d.display === "list") optList.selected = true;

      selDisplay.appendChild(optGrid);
      selDisplay.appendChild(optList);
      selDisplay.addEventListener("change", (e) => {
        d.display = e.target.value;
      });

      const btnDelete = document.createElement("button");
      btnDelete.type = "button";
      btnDelete.className = "btn-icon btn-delete";
      btnDelete.textContent = "✕";
      btnDelete.title = "Удалить этот раздел папки";
      btnDelete.addEventListener("click", () => {
        state.directories.splice(index, 1);
        renderDirectories();
      });

      headerRight.appendChild(selDisplay);
      headerRight.appendChild(btnDelete);

      headerDiv.appendChild(headerLeft);
      headerDiv.appendChild(headerRight);
      card.appendChild(headerDiv);

      // 2. PATH ROW (Путь к папке, Обзор, Открыть, Обновить)
      const pathRow = document.createElement("div");
      pathRow.className = "dir-path-row";

      const pathInput = document.createElement("input");
      pathInput.type = "text";
      pathInput.className = "form-control font-mono";
      pathInput.style.flex = "1";
      pathInput.value = d.path || "";
      pathInput.placeholder = "Путь к папке (например: !_материалы_фурнитура или C:/Projects/...)";
      pathInput.addEventListener("change", (e) => {
        d.path = e.target.value;
        callRuby("getFolderFiles", JSON.stringify({ index: index, path: d.path }));
      });
      pathInput.addEventListener("input", (e) => {
        d.path = e.target.value;
      });

      const btnBrowse = document.createElement("button");
      btnBrowse.type = "button";
      btnBrowse.className = "btn btn-xs btn-secondary";
      btnBrowse.textContent = "📂 Обзор";
      btnBrowse.title = "Выбрать существующую папку через проводник";
      btnBrowse.addEventListener("click", () => {
        callRuby("selectDirectory", index.toString());
      });

      const btnOpen = document.createElement("button");
      btnOpen.type = "button";
      btnOpen.className = "btn btn-xs btn-secondary";
      btnOpen.textContent = "↗ Открыть";
      btnOpen.title = "Открыть папку в проводнике Windows";
      btnOpen.addEventListener("click", () => {
        if (d.path) {
          callRuby("openDirectoryPath", d.path);
        } else {
          showNotification("Укажите путь к папке", "warning");
        }
      });
      const btnRefresh = document.createElement("button");
      btnRefresh.type = "button";
      btnRefresh.className = "btn btn-xs btn-secondary";
      btnRefresh.textContent = "🔄 Обновить";
      btnRefresh.title = "Пересканировать файлы в папке";
      btnRefresh.addEventListener("click", () => {
        if (d.path) {
          const badge = document.getElementById(`dirFileBadge_${index}`);
          const grid = document.getElementById(`dirPreviewGrid_${index}`);
          if (badge) {
            badge.textContent = "Сканирование...";
            badge.className = "badge badge-tag badge-grid";
          }
          if (grid) {
            grid.innerHTML = `<div class="dir-empty-state" style="grid-column: 1 / -1;">Загрузка файлов...</div>`;
          }
          if (state.folderFiles) delete state.folderFiles[index];
          scheduleScanTimeout(index, d.path);
          callRuby("getFolderFiles", JSON.stringify({ index: index, path: d.path }));
        } else {
          showNotification("Укажите путь к папке", "warning");
        }
      });

      pathRow.appendChild(pathInput);
      pathRow.appendChild(btnBrowse);
      pathRow.appendChild(btnOpen);
      pathRow.appendChild(btnRefresh);
      card.appendChild(pathRow);

      // 3. DESCRIPTION / SPECIFICATION BLOCK
      const descBlock = document.createElement("div");
      descBlock.className = "dir-desc-block";

      const descLabel = document.createElement("div");
      descLabel.className = "dir-desc-label";
      descLabel.innerHTML = `<span>📝 Описание и спецификация раздела:</span><span style="font-size: 10.5px; color: var(--text-dim);">Сохраняется в YAML и попадает в страницы проекта</span>`;

      const descTextarea = document.createElement("textarea");
      descTextarea.className = "form-control dir-desc-textarea";
      descTextarea.rows = 3;
      descTextarea.placeholder = "Опишите подробно спецификацию материалов, техники, фурнитуры, габаритов или особенности этого раздела...";
      descTextarea.value = d.description || "";
      descTextarea.addEventListener("input", (e) => {
        d.description = e.target.value;
      });

      descBlock.appendChild(descLabel);
      descBlock.appendChild(descTextarea);
      card.appendChild(descBlock);

      // 4. PREVIEWS BLOCK
      const previewBlock = document.createElement("div");
      previewBlock.className = "dir-preview-block";
      previewBlock.id = `dirPreviewBlock_${index}`;

      const previewHeader = document.createElement("div");
      previewHeader.className = "dir-preview-header";
      previewHeader.innerHTML = `
        <span style="display: flex; align-items: center; gap: 6px;">
          <span>🖼️ Превью файлов в папке:</span>
          <code style="font-size: 11px; color: var(--text-dim);">${d.path || "(папка не задана)"}</code>
        </span>
        <span class="badge badge-tag badge-grid" id="dirFileBadge_${index}">Сканирование...</span>`;

      const previewGrid = document.createElement("div");
      previewGrid.className = "dir-preview-grid";
      previewGrid.id = `dirPreviewGrid_${index}`;
      previewGrid.innerHTML = `<div class="dir-empty-state" style="grid-column: 1 / -1;">Загрузка файлов...</div>`;

      previewBlock.appendChild(previewHeader);
      previewBlock.appendChild(previewGrid);
      card.appendChild(previewBlock);

      els.directoriesCardsContainer.appendChild(card);

      // Запрашиваем файлы для папки, если путь указан
      if (d.path) {
        if (state.folderFiles && state.folderFiles[index] && state.folderFiles[index].path === d.path) {
          renderDirectoryPreview(index, state.folderFiles[index]);
        } else {
          scheduleScanTimeout(index, d.path);
          callRuby("getFolderFiles", JSON.stringify({ index: index, path: d.path }));
        }
      } else {
        const badge = document.getElementById(`dirFileBadge_${index}`);
        if (badge) {
          badge.textContent = "0 файлов";
          badge.className = "badge badge-tag badge-list";
        }
        previewGrid.innerHTML = `<div class="dir-empty-state" style="grid-column: 1 / -1;">📁 Путь к папке не задан. Нажмите «📂 Обзор», чтобы выбрать рабочую папку с файлами.</div>`;
      }
    });
  }

  // Render file previews for a specific directory card
  function renderDirectoryPreview(index, data) {
    clearScanTimeout(index);
    const gridEl = document.getElementById(`dirPreviewGrid_${index}`);
    const badgeEl = document.getElementById(`dirFileBadge_${index}`);
    if (!gridEl) return;

    if (!data.exists) {
      if (badgeEl) {
        badgeEl.textContent = "Не найдена";
        badgeEl.className = "badge badge-tag badge-list";
      }
      gridEl.innerHTML = `
        <div class="dir-empty-state" style="grid-column: 1 / -1; color: #b45309;">
          ⚠️ Папка не найдена на диске. Нажмите «📂 Обзор», чтобы указать существующий каталог.
        </div>`;
      return;
    }

    const files = data.files || [];
    if (badgeEl) {
      badgeEl.textContent = `${files.length} ${files.length === 1 ? "файл" : (files.length >= 2 && files.length <= 4 ? "файла" : "файлов")}`;
      badgeEl.className = files.length > 0 ? "badge badge-tag badge-grid" : "badge badge-tag badge-list";
    }

    if (files.length === 0) {
      gridEl.innerHTML = `
        <div class="dir-empty-state" style="grid-column: 1 / -1;">
          📁 Папка существует, но файлов в ней пока нет. Вы можете поместить в неё фото, замеры или спецификации.
        </div>`;
      return;
    }

    gridEl.innerHTML = "";
    files.forEach((file) => {
      const item = document.createElement("div");
      item.className = "dir-preview-item";
      item.title = `${file.name} (${formatFileSize(file.size)})\nНажмите, чтобы открыть файл`;

      const thumbWrap = document.createElement("div");
      thumbWrap.className = "dir-preview-thumb-wrap";

      if (file.is_image && file.url) {
        const img = document.createElement("img");
        img.src = file.url;
        img.alt = file.name;
        img.loading = "lazy";
        img.onerror = () => {
          img.remove();
          const docIcon = document.createElement("div");
          docIcon.className = "dir-preview-doc-icon";
          docIcon.innerHTML = `<span>🖼️</span><span class="dir-preview-doc-ext">${file.ext || "IMG"}</span>`;
          thumbWrap.appendChild(docIcon);
        };
        thumbWrap.appendChild(img);
      } else if (file.is_image) {
        const docIcon = document.createElement("div");
        docIcon.className = "dir-preview-doc-icon";
        docIcon.innerHTML = `<span>🖼️</span><span class="dir-preview-doc-ext">${file.ext || "IMG"}</span>`;
        thumbWrap.appendChild(docIcon);
      } else {
        const docIcon = document.createElement("div");
        docIcon.className = "dir-preview-doc-icon";
        docIcon.innerHTML = `<span>${getDocIcon(file.ext)}</span><span class="dir-preview-doc-ext">${file.ext}</span>`;
        thumbWrap.appendChild(docIcon);
      }

      const meta = document.createElement("div");
      meta.className = "dir-preview-meta";

      const nameDiv = document.createElement("div");
      nameDiv.className = "dir-preview-name";
      nameDiv.textContent = file.name;

      const sizeDiv = document.createElement("div");
      sizeDiv.className = "dir-preview-size";
      sizeDiv.textContent = formatFileSize(file.size);

      meta.appendChild(nameDiv);
      meta.appendChild(sizeDiv);

      item.appendChild(thumbWrap);
      item.appendChild(meta);

      item.addEventListener("click", () => {
        callRuby("openFolder", file.path);
      });

      gridEl.appendChild(item);
    });
  }

  // Render API Targets (api_targets from project_config.yaml)
  function renderApiTargets() {
    if (!els.apiTargetsList) return;
    els.apiTargetsList.innerHTML = "";
    const targets = state.api_targets || [];
    if (targets.length === 0) {
      els.apiTargetsList.innerHTML = `<div style="color:var(--text-dim);font-size:12px;padding:8px;">Адресаты API не заданы в project_config.yaml</div>`;
      return;
    }
    targets.forEach((targetUrl) => {
      const card = document.createElement("div");
      card.className = "api-target-card";
      card.innerHTML = `<span class="api-target-icon">🌐</span> <span>${targetUrl}</span>`;
      els.apiTargetsList.appendChild(card);
    });
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
    const layoutTab = document.getElementById("tab-scenes");
    if (layoutTab && layoutTab.classList.contains("active")) {
      renderLayoutCanvas();
    }
  }

  let draggedSceneIndex = null;

  function updateSceneBadge() {
    const activeCount = (state.scenes || []).filter(s => s.enabled !== false && s.page_type !== "skip").length;
    const totalCount = (state.scenes || []).length;
    if (els.sceneCountBadge) {
      els.sceneCountBadge.textContent = activeCount;
      els.sceneCountBadge.title = `Создаваемых страниц: ${activeCount} из ${totalCount}`;
    }
  }

  // Render Scenes Table
  function renderScenesTable() {
    els.scenesTableBody.innerHTML = "";
    const scenes = state.scenes || [];
    updateSceneBadge();

    scenes.forEach((scene, index) => {
      const tr = document.createElement("tr");
      tr.setAttribute("draggable", "true");
      tr.dataset.index = index;

      if (scene.page_type === layoutState.currentTemplate) {
        tr.classList.add("active-split-scene");
      }

      // Checkbox Enabled
      const tdCheck = document.createElement("td");
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = scene.enabled !== false;
      chk.title = "Включить / исключить сцену из экспорта в PDF";
      chk.addEventListener("change", (e) => {
        scene.enabled = e.target.checked;
        updateSceneBadge();
        renderLayoutCanvas();
        updateLayoutUsageBadge();
      });
      chk.addEventListener("click", (e) => e.stopPropagation());
      tdCheck.appendChild(chk);

      // Index & Drag Handle
      const tdNum = document.createElement("td");
      tdNum.style.whiteSpace = "nowrap";
      tdNum.title = "Перетащите строку мышью для изменения порядка";
      const dragHandle = document.createElement("span");
      dragHandle.className = "drag-handle";
      dragHandle.textContent = "⠿";
      const rowNum = document.createElement("span");
      rowNum.className = "row-num";
      rowNum.textContent = index + 1;
      tdNum.appendChild(dragHandle);
      tdNum.appendChild(rowNum);

      // Scene Name (Editable)
      const tdName = document.createElement("td");
      const inputName = document.createElement("input");
      inputName.type = "text";
      inputName.className = "table-input scene-name-input";
      inputName.value = scene.name || "";
      inputName.placeholder = "Название сцены...";
      inputName.title = "Редактировать название сцены";
      inputName.addEventListener("input", (e) => {
        scene.name = e.target.value;
        renderLayoutCanvas();
      });
      inputName.addEventListener("change", (e) => {
        scene.name = e.target.value.trim();
        e.target.value = scene.name;
        renderTemplateSettingsList();
        updateLayoutUsageBadge();
      });
      inputName.addEventListener("keydown", (e) => {
        if (e.key === "Enter") inputName.blur();
      });
      inputName.addEventListener("click", (e) => e.stopPropagation());
      tdName.appendChild(inputName);

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
        updateSceneBadge();
        layoutState.currentTemplate = e.target.value;
        if (els.selectLayoutTemplate) {
          els.selectLayoutTemplate.value = e.target.value;
        }
        renderLayoutCanvas();
        updateLayoutUsageBadge();
      });
      selType.addEventListener("click", (e) => e.stopPropagation());
      tdType.appendChild(selType);

      // Description Input
      const tdDesc = document.createElement("td");
      const inputDesc = document.createElement("input");
      inputDesc.type = "text";
      inputDesc.className = "table-input";
      inputDesc.value = scene.description || "";
      inputDesc.placeholder = "Примечание к виду...";
      inputDesc.title = "Описание / примечание на листе";
      inputDesc.addEventListener("input", (e) => {
        scene.description = e.target.value;
        renderLayoutCanvas();
      });
      inputDesc.addEventListener("change", (e) => {
        scene.description = e.target.value.trim();
        e.target.value = scene.description;
        renderTemplateSettingsList();
      });
      inputDesc.addEventListener("keydown", (e) => {
        if (e.key === "Enter") inputDesc.blur();
      });
      inputDesc.addEventListener("click", (e) => e.stopPropagation());
      tdDesc.appendChild(inputDesc);

      // Drag and Drop event listeners for row reordering
      tr.addEventListener("mousedown", (e) => {
        if (e.target.closest("input, select, button, a")) {
          tr.setAttribute("draggable", "false");
        } else {
          tr.setAttribute("draggable", "true");
        }
      });

      tr.addEventListener("mouseup", () => {
        tr.setAttribute("draggable", "true");
      });

      tr.addEventListener("dragstart", (e) => {
        draggedSceneIndex = index;
        tr.classList.add("dragging");
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", index.toString());
      });

      tr.addEventListener("dragend", () => {
        tr.classList.remove("dragging");
        draggedSceneIndex = null;
        els.scenesTableBody.querySelectorAll("tr").forEach((row) => {
          row.classList.remove("drag-over-top", "drag-over-bottom");
        });
      });

      tr.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (draggedSceneIndex === null || draggedSceneIndex === index) return;

        const rect = tr.getBoundingClientRect();
        const relY = e.clientY - rect.top;
        const isTop = relY < rect.height / 2;

        tr.classList.toggle("drag-over-top", isTop);
        tr.classList.toggle("drag-over-bottom", !isTop);
      });

      tr.addEventListener("dragleave", () => {
        tr.classList.remove("drag-over-top", "drag-over-bottom");
      });

      tr.addEventListener("drop", (e) => {
        e.preventDefault();
        e.stopPropagation();
        tr.classList.remove("drag-over-top", "drag-over-bottom");

        if (draggedSceneIndex === null || draggedSceneIndex === index) return;

        const rect = tr.getBoundingClientRect();
        const relY = e.clientY - rect.top;
        const isTop = relY < rect.height / 2;

        let dropIndex = index;
        if (!isTop) {
          dropIndex = index + 1;
        }
        if (draggedSceneIndex < dropIndex) {
          dropIndex -= 1;
        }

        if (dropIndex !== draggedSceneIndex) {
          const item = state.scenes.splice(draggedSceneIndex, 1)[0];
          state.scenes.splice(dropIndex, 0, item);
          state.scenes.forEach((s, idx) => (s.order = idx));
          renderScenesTable();
          updateLayoutUsageBadge();
          if (layoutTab && layoutTab.classList.contains("active")) {
            renderLayoutCanvas();
          }
        }
      });

      // Click on row in split view to focus template
      tr.addEventListener("click", () => {
        const tpl = scene.page_type || "cover";
        layoutState.currentTemplate = tpl;
        layoutState.selectedSceneIndex = index;
        if (els.selectLayoutTemplate) {
          els.selectLayoutTemplate.value = tpl;
        }
        renderLayoutCanvas();
        renderTemplateSettingsList();
        updateLayoutUsageBadge();
      });

      tr.appendChild(tdCheck);
      tr.appendChild(tdNum);
      tr.appendChild(tdName);
      tr.appendChild(tdDesc);
      tr.appendChild(tdType);

      els.scenesTableBody.appendChild(tr);
    });

    updateLayoutUsageBadge();
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
      inputDesc.value = item.text || item.description || "";
      inputDesc.placeholder = "Текст правки / комментарий...";
      inputDesc.addEventListener("input", (e) => {
        item.text = e.target.value;
        item.description = e.target.value;
        // Синхронизируем верхнюю (самую свежую) запись с полем last_edit
        if (index === 0 && els.inputLastEdit) {
          els.inputLastEdit.value = e.target.value;
        }
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
    const articulVal = (els.inputArticul ? els.inputArticul.value : "").trim();
    const custVal = (els.inputCustomer ? els.inputCustomer.value : "").trim();
    const compVal = (els.inputCompany ? els.inputCompany.value : "").trim();
    const addrVal = (els.inputAddress ? els.inputAddress.value : "").trim();
    const isCommercial = els.selectTrade ? (els.selectTrade.value === "1") : articulVal.startsWith("CF#");
    const tradeVal = isCommercial ? "1" : "0";
    const lastEditVal = (els.inputLastEdit ? els.inputLastEdit.value : "").trim();
    const tagsVal = (els.inputTags ? els.inputTags.value : "").trim();
    const descVal = (els.inputProjectDescription ? els.inputProjectDescription.value : "").trim();
    const custIdVal = (els.inputCustomerId ? els.inputCustomerId.value : "").trim();
    const phoneVal = (els.inputPhone ? els.inputPhone.value : "").trim();
    const emailVal = (els.inputEmail ? els.inputEmail.value : "").trim();
    const authorVal = (els.inputAuthor ? els.inputAuthor.value : "").trim();
    const priceVal = (els.inputPrice ? els.inputPrice.value : "").trim();
    const startDateVal = (els.inputStartDate ? els.inputStartDate.value : "").trim();
    const endDateVal = (els.inputEndDate ? els.inputEndDate.value : "").trim();
    const totalDurationVal = (els.inputTotalDuration ? els.inputTotalDuration.value : "").trim();
    const statusVal = els.inputStatus ? els.inputStatus.value : "Предварительный";
    const revVal = parseInt(els.inputRevision ? els.inputRevision.value : 1, 10) || 1;
    const verVal = parseInt(els.inputVersion ? els.inputVersion.value : 1, 10) || 1;

    // Синхронизируем history_edit пары [дата, текст]
    const historyEditPairs = (state.history || []).map((item) => [
      item.date || "",
      item.text || item.description || ""
    ]);

    // Модуль 1: Project
    state.project = {
      articul: articulVal,
      product: furniture,
      place: room,
      adress: addrVal,
      description: descVal,
      tags: tagsVal,
      commercial: isCommercial,
      name_company: compVal
    };

    // Модуль 2: Customer
    state.customer = {
      id: custIdVal,
      name: custVal,
      phone: phoneVal,
      email: emailVal
    };

    // Модуль 3: Workflow
    state.workflow = {
      author: authorVal,
      price: priceVal,
      start_date: startDateVal,
      end_date: endDateVal,
      total_duration: totalDurationVal,
      status: statusVal,
      version: verVal,
      revision: revVal,
      history_edit: historyEditPairs
    };

    // Фасад project_info для 100% обратной совместимости
    state.project_info = {
      articul:          articulVal,
      name_product:     furniture,
      name_place:       room,
      adress:           addrVal,
      customer:         custVal,
      company:          compVal,
      status:           statusVal,
      revision:         revVal,
      version:          verVal,
      last_edit:        lastEditVal,
      trade:            tradeVal,
      tags:             tagsVal,
      description:      descVal,
      room_name:        room,
      furniture_name:   furniture,
      name_project:     computedTitle,
      name_customer:    custVal,
      address:          addrVal,
      edit:             lastEditVal,
      phone:            phoneVal,
      email:            emailVal,
      author:           authorVal,
      price:            priceVal,
      task_description: (els.inputTaskDescription ? els.inputTaskDescription.value : "").trim() || descVal,
      task_dimensions:  (els.inputTaskDimensions ? els.inputTaskDimensions.value : "").trim(),
      task_wishes:      (els.inputTaskWishes ? els.inputTaskWishes.value : "").trim(),
      materials:        (els.inputMaterials ? els.inputMaterials.value : "").trim(),
      appliances:       (els.inputAppliances ? els.inputAppliances.value : "").trim(),
      lighting:         (els.inputLighting ? els.inputLighting.value : "").trim(),
      notes:            (els.inputNotes ? els.inputNotes.value : "").trim()
    };

    // Синхронизация спецификаций из карточек directories
    if (Array.isArray(state.directories)) {
      state.directories.forEach((d) => {
        const p = (d.path || "").toLowerCase();
        const t = (d.title || "").toLowerCase();
        const desc = (d.description || "").trim();
        if (!desc) return;
        if (p.includes("материал") || t.includes("материал") || p.includes("фурнитур") || t.includes("фурнитур")) {
          state.project_info.materials = desc;
        } else if (p.includes("техник") || t.includes("техник") || p.includes("подсветк") || t.includes("подсветк")) {
          if (!state.project_info.appliances) state.project_info.appliances = desc;
          if (!state.project_info.lighting) state.project_info.lighting = desc;
        } else if (p.includes("замер") || t.includes("замер")) {
          if (!state.project_info.task_dimensions) state.project_info.task_dimensions = desc;
        } else if (p.includes("инфо") || t.includes("инфо") || p.includes("заказчик") || t.includes("заказчик")) {
          if (!state.project_info.notes) state.project_info.notes = desc;
        }
      });
    }

    ensureCustomLayouts();

    state.pdf_settings = {
      export_engine: els.selectExportEngine ? els.selectExportEngine.value : "prawn",
      layout_render_mode: els.selectLayoutRenderMode ? els.selectLayoutRenderMode.value : "raster",
      save_layout_file: els.chkSaveLayoutFile ? els.chkSaveLayoutFile.checked : true,
      page_size: els.selectPageSize.value,
      page_layout: els.selectPageLayout.value,
      margin_mm: els.inputPageMargin ? parseFloat(els.inputPageMargin.value) || 0 : (state.pdf_settings?.margin_mm ?? 5),
      margin: Math.round((((els.inputPageMargin ? parseFloat(els.inputPageMargin.value) || 0 : (state.pdf_settings?.margin_mm ?? 5)) * 72.0) / 25.4) * 10) / 10,
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

  // Trigger Articul Generation
  function triggerGenerateArticul() {
    const isCommercial = els.selectTrade ? (els.selectTrade.value === "1") : false;
    if (window.sketchup && typeof window.sketchup.generateArticul === "function") {
      callRuby("generateArticul", JSON.stringify({ commercial: isCommercial, index: 1 }));
    } else {
      const newArt = generateArticulLocal(isCommercial, 1);
      if (els.inputArticul) {
        els.inputArticul.value = newArt;
        updateHeaderTitles();
        showNotification(`Сгенерирован артикул: ${newArt}`, "info");
      }
    }
  }

  // Trigger Customer ID Generation
  function triggerGenerateCustomerId() {
    const custName = (els.inputCustomer ? els.inputCustomer.value : "").trim();
    if (window.sketchup && typeof window.sketchup.generateCustomerId === "function") {
      callRuby("generateCustomerId", custName);
    } else {
      const newId = generateCustomerIdLocal();
      if (els.inputCustomerId) {
        els.inputCustomerId.value = newId;
        showNotification(`Сгенерирован ID заказчика: ${newId}`, "info");
      }
    }
  }

  // Event Listeners Initialization
  function setupEventListeners() {
    // Dynamic update of header titles
    els.inputRoomName.addEventListener("input", updateHeaderTitles);
    els.inputFurnitureName.addEventListener("input", updateHeaderTitles);
    els.inputCustomer.addEventListener("input", updateHeaderTitles);
    els.inputAddress.addEventListener("input", updateHeaderTitles);

    if (els.btnGenerateArticul) {
      els.btnGenerateArticul.addEventListener("click", triggerGenerateArticul);
    }
    if (els.btnGenerateCustomerId) {
      els.btnGenerateCustomerId.addEventListener("click", triggerGenerateCustomerId);
    }

    if (els.selectTrade) {
      els.selectTrade.addEventListener("change", () => {
        updateCompanyVisibility();
        const isComm = els.selectTrade.value === "1";
        const curArt = (els.inputArticul ? els.inputArticul.value : "").trim();
        if (curArt.startsWith("CF#") && !isComm) {
          els.inputArticul.value = curArt.replace(/^CF#/, "HF#");
          updateHeaderTitles();
        } else if (curArt.startsWith("HF#") && isComm) {
          els.inputArticul.value = curArt.replace(/^HF#/, "CF#");
          updateHeaderTitles();
        }
      });
    }

    if (els.inputArticul) {
      els.inputArticul.addEventListener("input", () => {
        updateHeaderTitles();
        const val = els.inputArticul.value.trim();
        if (els.selectTrade) {
          if (val.startsWith("CF#")) {
            els.selectTrade.value = "1";
          } else if (val.startsWith("HF#")) {
            els.selectTrade.value = "0";
          }
          updateCompanyVisibility();
        }
      });
    }

    // Directories Add button
    if (els.btnAddDirectory) {
      els.btnAddDirectory.addEventListener("click", () => {
        if (!Array.isArray(state.directories)) state.directories = [];
        state.directories.push({
          path: "!_новые_материалы",
          title: "Новый раздел",
          description: "Дополнительное описание",
          display: "grid"
        });
        renderDirectories();
      });
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

    const handleMarginChange = (val) => {
      const num = Math.max(0, Math.min(100, parseFloat(val) || 0));
      if (els.inputPageMargin && parseFloat(els.inputPageMargin.value) !== num) els.inputPageMargin.value = num;
      if (els.inputLayoutMargin && parseFloat(els.inputLayoutMargin.value) !== num) els.inputLayoutMargin.value = num;
      if (state.pdf_settings) {
        state.pdf_settings.margin_mm = num;
        state.pdf_settings.margin = Math.round(((num * 72.0) / 25.4) * 10) / 10;
      }
      renderLayoutCanvas();
    };

    if (els.inputPageMargin) {
      els.inputPageMargin.addEventListener("input", (e) => handleMarginChange(e.target.value));
    }
    if (els.inputLayoutMargin) {
      els.inputLayoutMargin.addEventListener("input", (e) => handleMarginChange(e.target.value));
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

    // Add History Entry (edit_history.yaml)
    els.btnAddHistoryEntry.addEventListener("click", () => {
      const now = new Date();
      const y = now.getFullYear();
      const m = String(now.getMonth() + 1).padStart(2, '0');
      const d = String(now.getDate()).padStart(2, '0');
      const hh = String(now.getHours()).padStart(2, '0');
      const mm = String(now.getMinutes()).padStart(2, '0');
      const nowStr = `${y}-${m}-${d} ${hh}:${mm}`;
      const defaultText = "Новые правки";

      state.history.unshift({
        date: nowStr,
        text: defaultText,
        description: defaultText
      });

      if (els.inputLastEdit) els.inputLastEdit.value = defaultText;
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

    onArticulGenerated: function (newArticul) {
      if (els.inputArticul && newArticul) {
        els.inputArticul.value = newArticul;
        updateHeaderTitles();
        showNotification(`Сгенерирован артикул: ${newArticul}`, "info");
      }
    },

    onCustomerIdGenerated: function (newCustomerId) {
      if (els.inputCustomerId && newCustomerId) {
        els.inputCustomerId.value = newCustomerId;
        showNotification(`Сгенерирован ID заказчика: ${newCustomerId}`, "info");
      }
    },

    onDirectorySelected: function (index, chosenPath) {
      const idx = parseInt(index, 10);
      if (Array.isArray(state.directories) && state.directories[idx]) {
        state.directories[idx].path = chosenPath;
        renderDirectories();
        showNotification(`Выбрана папка: ${chosenPath}`, "info");
      }
    },

    onFolderFilesLoaded: function (data) {
      if (!data) return;
      state.folderFiles = state.folderFiles || {};
      state.folderFiles[data.index] = data;
      renderDirectoryPreview(data.index, data);
    },

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
    setupSplitResizer();
    setupScrollWheelHandlers();

    // Request initial data from SketchUp
    callRuby("getData");
  });
})();
