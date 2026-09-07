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

  const DEFAULT_MIDDLE_ALIGNS = {
    toc_pages: "left", spec_materials: "left", spec_appliances: "left", general_notes: "left",
    workflow_history: "left", workflow_stadia: "left", workflow_revision: "left",
    workflow_version: "left", workflow_date: "left", articul: "left"
  };

  const DEFAULT_MIDDLE_VALIGNS = {
    toc_pages: "top", spec_materials: "top", spec_appliances: "top", general_notes: "top",
    workflow_history: "bottom", workflow_stadia: "bottom", workflow_revision: "bottom",
    workflow_version: "bottom", workflow_date: "bottom", articul: "bottom"
  };

  const DEFAULT_MIDDLE_SIZES = {
    toc_pages: 8, spec_materials: 8, spec_appliances: 8, general_notes: 8,
    workflow_history: 8, workflow_stadia: 8, workflow_revision: 8,
    workflow_version: 8, workflow_date: 8, articul: 8
  };

  const DEFAULT_MIDDLE_COLORS = {
    toc_pages: "#334155", spec_materials: "#334155", spec_appliances: "#334155", general_notes: "#334155",
    workflow_history: "#334155", workflow_stadia: "#334155", workflow_revision: "#334155",
    workflow_version: "#334155", workflow_date: "#334155", articul: "#334155"
  };

  // 7 Standard Layout Zones (matching user sketch wireframe)
  const FIXED_SLOT_DEFS = [
    {
      id: "image_4_3",
      label: "КАРТИНКА ПРОЕКТА",
      icon: "🖼️",
      slot_class: "slot-image-4-3",
      x: 0.0, y: 0.0, w: 100.0, h: 100.0,
      aspect_ratio: "4:3",
      scale_pct: 100,
      is_image: true
    },
    {
      id: "header",
      label: "ЗАГОЛОВОК",
      icon: "🔝",
      slot_class: "slot-header",
      default_content: "header_title",
      x: 0.0, y: 0.0, w: 100.0, h: 30.0,
      valign: "top",
      default_valign: "top",
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
      default_content: "info_lines",
      x: 0.0, y: 0.0, w: 25.0, h: 58.0,
      default_lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"],
      default_line_aligns: Object.assign({}, DEFAULT_MIDDLE_ALIGNS),
      default_line_valigns: Object.assign({}, DEFAULT_MIDDLE_VALIGNS),
      default_line_font_sizes: Object.assign({}, DEFAULT_MIDDLE_SIZES),
      default_line_colors: Object.assign({}, DEFAULT_MIDDLE_COLORS)
    },
    {
      id: "slot_3",
      label: "ПРАВЫЙ ВЕРХ",
      icon: "⬛",
      slot_class: "slot-3",
      default_content: "info_lines",
      x: 75.0, y: 0.0, w: 25.0, h: 58.0,
      default_lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"]
    },
    {
      id: "slot_2",
      label: "ЛЕВЫЙ НИЗ",
      icon: "⬛",
      slot_class: "slot-2",
      default_content: "info_lines",
      x: 0.0, y: 58.0, w: 25.0, h: 36.0,
      default_lines: ["workflow_history", "workflow_stadia"]
    },
    {
      id: "slot_4",
      label: "ПРАВЫЙ НИЗ",
      icon: "⬛",
      slot_class: "slot-4",
      default_content: "info_lines",
      x: 75.0, y: 58.0, w: 25.0, h: 36.0,
      default_lines: ["workflow_history", "workflow_stadia"]
    },
    {
      id: "footer",
      label: "ПОДВАЛ",
      icon: "📑",
      slot_class: "slot-footer",
      default_content: "footer_info",
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
    { key: "spec_materials",   group: "specs",    label: "Материалы и фурнитура",   icon: "🛠️", getVal: (info, wf) => (info.materials || "").trim() || "Фасады МДФ, ЛДСП, Blum..." },
    { key: "spec_appliances",  group: "specs",    label: "Техника и подсветка",     icon: "🔌", getVal: (info, wf) => [info.appliances, info.lighting].filter(Boolean).map(s => s.trim()).filter(Boolean).join("; ") || "Встраиваемая техника, LED 3000K..." },
    { key: "general_notes",    group: "project",  label: "Общие пояснения",         icon: "📝", getVal: (info, wf) => (info.project_description || info.description || info.notes || "").trim() || "Замеры выполнены по факту" },
    { key: "workflow_history", group: "workflow", label: "История правок",          icon: "📜", getVal: (info, wf) => {
        const h = wf.history_edit || info.history_edit;
        if (Array.isArray(h) && h.length > 0) {
          return h.map(e => Array.isArray(e) ? `${e[0]} ${e[1]}` : String(e)).join(" • ");
        }
        return (wf.last_edit || info.last_edit || "").trim() || "Корректировка фасадов";
      }
    },
    { key: "workflow_stadia",  group: "workflow", label: "Стадия проекта",          icon: "⏳", getVal: (info, wf) => {
        const s = wf.stadia || info.stadia;
        if (Array.isArray(s) && s.length > 0) {
          return s.map(st => Array.isArray(st) ? `${st[1] ? "[✓]" : "[ ]"} ${st[2]}` : String(st)).join(" • ");
        }
        return (wf.status || info.status || "").trim() || "РД";
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

  // Deep clone utility to guarantee complete independence of template slot settings
  function deepClone(obj) {
    if (obj === null || typeof obj !== "object") return obj;
    if (Array.isArray(obj)) return obj.map(deepClone);
    const copy = {};
    for (const k of Object.keys(obj)) {
      copy[k] = deepClone(obj[k]);
    }
    return copy;
  }

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
    valign: "top",
    font_size: 11,
    lines: ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"],
    line_rows: { furniture_name: 1, place_address: 2, customer_or_company: 3, scene_name: 4, scene_description: 5 },
    line_font_sizes: { furniture_name: 11, place_address: 10, customer_or_company: 10, scene_name: 11, scene_description: 9 },
    line_colors: { furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A", scene_name: "#005EB0", scene_description: "#475569" },
    opacity: 0.95
  };

  const DEFAULT_MIDDLE_SLOT = {
    visible: true,
    content: "info_lines",
    align: "left",
    valign: "top",
    font_size: 8,
    item_gap_mm: 2,
    item_gap: 2,
    lines: ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia", "workflow_revision", "workflow_version", "workflow_date", "articul"],
    line_aligns: Object.assign({}, DEFAULT_MIDDLE_ALIGNS),
    line_valigns: Object.assign({}, DEFAULT_MIDDLE_VALIGNS),
    line_font_sizes: Object.assign({}, DEFAULT_MIDDLE_SIZES),
    line_colors: Object.assign({}, DEFAULT_MIDDLE_COLORS),
    opacity: 0.9
  };

  // Factory function to ensure each template receives 100% independent deep-cloned slot instances
  function createDefaultHeaderSlot() {
    return deepClone(DEFAULT_HEADER_SLOT);
  }

  function createDefaultMiddleSlot(overrides = {}) {
    return Object.assign(deepClone(DEFAULT_MIDDLE_SLOT), deepClone(overrides));
  }

  // Default block configurations for each page template (strictly independent & purpose-tailored)
  const DEFAULT_LAYOUTS = {
    cover: {
      name: "Титульный лист (Cover)",
      slots: {
        header: {
          visible: true,
          content: "header_title",
          valign: "top",
          font_size: 13,
          lines: ["furniture_name", "place_address", "customer_or_company"],
          line_rows: { furniture_name: 1, place_address: 2, customer_or_company: 3, scene_name: 4, scene_description: 5 },
          line_font_sizes: { furniture_name: 14, place_address: 11, customer_or_company: 11, scene_name: 11, scene_description: 9 },
          line_colors: { furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A", scene_name: "#005EB0", scene_description: "#475569" },
          opacity: 0.95
        },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 80 },
        slot_1: {
          visible: true,
          content: "info_lines",
          align: "left",
          valign: "top",
          font_size: 8.5,
          item_gap_mm: 3.0,
          lines: ["articul", "workflow_date", "workflow_version", "workflow_revision", "workflow_stadia"],
          line_aligns: { articul: "left", workflow_date: "left", workflow_version: "left", workflow_revision: "left", workflow_stadia: "left" },
          line_valigns: { articul: "top", workflow_date: "top", workflow_version: "top", workflow_revision: "bottom", workflow_stadia: "bottom" },
          line_font_sizes: { articul: 9, workflow_date: 8.5, workflow_version: 8.5, workflow_revision: 8.5, workflow_stadia: 8.5 },
          line_colors: { articul: "#005EB0", workflow_date: "#334155", workflow_version: "#334155", workflow_revision: "#334155", workflow_stadia: "#334155" },
          opacity: 0.92
        },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        slot_3: { visible: false, content: "none", align: "right", valign: "top", font_size: 8, lines: [], opacity: 0.9 },
        slot_4: { visible: false, content: "none", align: "right", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        footer: { visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    description: {
      name: "Описание и спецификации (Description)",
      slots: {
        header: {
          visible: true,
          content: "header_title",
          valign: "top",
          font_size: 11,
          lines: ["furniture_name", "place_address", "scene_name", "scene_description"],
          line_rows: { furniture_name: 1, place_address: 2, scene_name: 3, scene_description: 4, customer_or_company: 5 },
          line_font_sizes: { furniture_name: 11, place_address: 10, scene_name: 11, scene_description: 9, customer_or_company: 10 },
          line_colors: { furniture_name: "#005EB0", place_address: "#0F172A", scene_name: "#005EB0", scene_description: "#475569", customer_or_company: "#0F172A" },
          opacity: 0.95
        },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 70 },
        slot_1: {
          visible: true,
          content: "info_lines",
          align: "left",
          valign: "top",
          font_size: 8.5,
          item_gap_mm: 2.5,
          lines: ["spec_materials", "spec_appliances", "general_notes"],
          line_aligns: { spec_materials: "left", spec_appliances: "left", general_notes: "left" },
          line_valigns: { spec_materials: "top", spec_appliances: "top", general_notes: "top" },
          line_font_sizes: { spec_materials: 8.5, spec_appliances: 8.5, general_notes: 8.5 },
          line_colors: { spec_materials: "#334155", spec_appliances: "#334155", general_notes: "#334155" },
          opacity: 0.92
        },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        slot_3: { visible: true, content: "info_lines", align: "right", valign: "top", font_size: 8.5, lines: ["spec_materials", "spec_appliances"], opacity: 0.9 },
        slot_4: { visible: false, content: "none", align: "right", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        footer: { visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    explain: {
      name: "Содержание и ведомость (Explain)",
      slots: {
        header: {
          visible: true,
          content: "header_title",
          valign: "top",
          font_size: 11,
          lines: ["furniture_name", "customer_or_company", "scene_name", "scene_description"],
          line_rows: { furniture_name: 1, customer_or_company: 2, scene_name: 3, scene_description: 4, place_address: 5 },
          line_font_sizes: { furniture_name: 11, customer_or_company: 10, scene_name: 11, scene_description: 9, place_address: 10 },
          line_colors: { furniture_name: "#005EB0", customer_or_company: "#0F172A", scene_name: "#005EB0", scene_description: "#475569", place_address: "#0F172A" },
          opacity: 0.95
        },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 60 },
        slot_1: {
          visible: true,
          content: "info_lines",
          align: "left",
          valign: "top",
          font_size: 8,
          item_gap_mm: 2.0,
          lines: ["toc_pages", "general_notes", "workflow_history", "workflow_stadia"],
          line_aligns: { toc_pages: "left", general_notes: "left", workflow_history: "left", workflow_stadia: "left" },
          line_valigns: { toc_pages: "top", general_notes: "top", workflow_history: "bottom", workflow_stadia: "bottom" },
          line_font_sizes: { toc_pages: 8, general_notes: 8, workflow_history: 8, workflow_stadia: 8 },
          line_colors: { toc_pages: "#334155", general_notes: "#334155", workflow_history: "#334155", workflow_stadia: "#334155" },
          opacity: 0.92
        },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        slot_3: { visible: true, content: "info_lines", align: "right", valign: "top", font_size: 8, lines: ["toc_pages", "workflow_history"], opacity: 0.9 },
        slot_4: { visible: false, content: "none", align: "right", valign: "bottom", font_size: 8, lines: [], opacity: 0.9 },
        footer: { visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    general: {
      name: "Общий вид (General)",
      slots: {
        header: {
          visible: true,
          content: "header_title",
          valign: "top",
          font_size: 11,
          lines: ["scene_name", "scene_description", "furniture_name", "place_address"],
          line_rows: { scene_name: 1, scene_description: 2, furniture_name: 3, place_address: 4, customer_or_company: 5 },
          line_font_sizes: { scene_name: 12, scene_description: 9, furniture_name: 10, place_address: 10, customer_or_company: 10 },
          line_colors: { scene_name: "#005EB0", scene_description: "#475569", furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A" },
          opacity: 0.95
        },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "16:9", scale_pct: 100 },
        slot_1: {
          visible: false,
          content: "none",
          align: "left",
          valign: "top",
          font_size: 8,
          item_gap_mm: 2.0,
          lines: [],
          opacity: 0.88
        },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0.88 },
        slot_3: { visible: false, content: "none", align: "right", valign: "top", font_size: 8, lines: [], opacity: 0.88 },
        slot_4: {
          visible: true,
          content: "info_lines",
          align: "right",
          valign: "bottom",
          font_size: 8,
          lines: ["workflow_history", "workflow_stadia"],
          line_aligns: { workflow_history: "right", workflow_stadia: "right" },
          line_valigns: { workflow_history: "bottom", workflow_stadia: "bottom" },
          opacity: 0.9
        },
        footer: { visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"], line_aligns: { footer_last_edit: "left", footer_ver_rev: "center", footer_articul: "center", footer_date: "center", footer_page_total: "right" }, opacity: 1.0 }
      }
    },
    visual: {
      name: "Визуализация (Visual)",
      slots: {
        header: {
          visible: true,
          content: "header_title",
          valign: "top",
          font_size: 10,
          lines: ["scene_name", "scene_description"],
          line_rows: { scene_name: 1, scene_description: 2, furniture_name: 3, place_address: 4, customer_or_company: 5 },
          line_font_sizes: { scene_name: 11, scene_description: 9, furniture_name: 10, place_address: 10, customer_or_company: 10 },
          line_colors: { scene_name: "#005EB0", scene_description: "#475569", furniture_name: "#005EB0", place_address: "#0F172A", customer_or_company: "#0F172A" },
          opacity: 0.95
        },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "16:9", scale_pct: 100 },
        slot_1: {
          visible: false,
          content: "none",
          align: "left",
          valign: "top",
          font_size: 8,
          item_gap_mm: 2.0,
          lines: [],
          opacity: 0.88
        },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0.88 },
        slot_3: { visible: false, content: "none", align: "right", valign: "top", font_size: 8, lines: [], opacity: 0.88 },
        slot_4: { visible: false, content: "none", align: "right", valign: "bottom", font_size: 8, lines: [], opacity: 0.88 },
        footer: { visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: ["footer_ver_rev", "footer_page_total"], line_aligns: { footer_ver_rev: "left", footer_page_total: "right" }, opacity: 1.0 }
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
    stadiaCheckboxesContainer: document.getElementById("stadiaCheckboxesContainer"),
    inputLastEdit: document.getElementById("inputLastEdit"),

    // Tab Directories
    directoriesCardsContainer: document.getElementById("directoriesCardsContainer"),
    btnAddDirectory: document.getElementById("btnAddDirectory"),

    // Tab Settings
    apiTargetsList: document.getElementById("apiTargetsList"),
    btnAddApiTarget: document.getElementById("btnAddApiTarget"),

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
    selectImageAspect: document.getElementById("selectImageAspect"),
    customAspectGroup: document.getElementById("customAspectGroup"),
    inputAspectCustomW: document.getElementById("inputAspectCustomW"),
    inputAspectCustomH: document.getElementById("inputAspectCustomH"),
    chkShowAspectOverlay: document.getElementById("chkShowAspectOverlay"),
    aspectOverlayBadge: document.getElementById("aspectOverlayBadge"),
    selectQuality: document.getElementById("selectQuality"),
    selectStamp: document.getElementById("selectStamp"),
    customStampGroup: document.getElementById("customStampGroup"),
    inputCustomStamp: document.getElementById("inputCustomStamp"),
    inputPrimaryColor: document.getElementById("inputPrimaryColor"),
    primaryColorHex: document.getElementById("primaryColorHex"),
    inputStampColor: document.getElementById("inputStampColor"),
    stampColorHex: document.getElementById("stampColorHex"),
    inputOverlayBorderColor: document.getElementById("inputOverlayBorderColor"),
    overlayBorderColorHex: document.getElementById("overlayBorderColorHex"),
    inputOverlayMaskColor: document.getElementById("inputOverlayMaskColor"),
    overlayMaskColorHex: document.getElementById("overlayMaskColorHex"),
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
    btnCloseSuccessModal: document.getElementById("btnCloseSuccessModal"),

    // Revision Prompt Modal
    revisionPromptModal: document.getElementById("revisionPromptModal"),
    revPromptDateTime: document.getElementById("revPromptDateTime"),
    revPromptCurrentRev: document.getElementById("revPromptCurrentRev"),
    revPromptNextRev: document.getElementById("revPromptNextRev"),
    inputRevisionNote: document.getElementById("inputRevisionNote"),
    btnConfirmRevisionExport: document.getElementById("btnConfirmRevisionExport"),
    btnSkipRevisionExport: document.getElementById("btnSkipRevisionExport"),
    btnCancelExportModal: document.getElementById("btnCancelExportModal")
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
        badge.title = `Сцены SketchUp, использующие этот шаблон: ${names}`;
        badge.classList.remove("empty-usage");
        badge.style.display = "flex";
      } else {
        badge.textContent = "Не привязан к сценам";
        badge.title = "Данный шаблон сейчас не назначен ни одной из сцен SketchUp";
        badge.classList.add("empty-usage");
        badge.style.display = "flex";
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

  // Auto-Save Engine (Debounced automatic persistence to YAML)
  let autoSaveTimer = null;
  function updateAutoSaveIndicator(status, text) {
    const statusEl = document.getElementById("autosaveStatus");
    const textEl = document.getElementById("autosaveText");
    if (!statusEl) return;
    statusEl.classList.remove("saving", "error");
    if (status === "saving") {
      statusEl.classList.add("saving");
      if (textEl) textEl.textContent = text || "Сохранение...";
      statusEl.title = "Выполняется автосохранение параметров в YAML...";
    } else if (status === "saved") {
      if (textEl) textEl.textContent = text || "Сохранено";
      statusEl.title = `Изменения сохранены: ${text || ""}`.trim();
    } else if (status === "error") {
      statusEl.classList.add("error");
      if (textEl) textEl.textContent = text || "Ошибка автосохранения";
      statusEl.title = "Не удалось сохранить файл YAML";
    }
  }

  function triggerAutoSave() {
    updateAutoSaveIndicator("saving", "Сохранение...");
    clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(() => {
      try {
        if (typeof collectFormData === "function") {
          const formData = collectFormData();
          const payload = Object.assign({}, formData, {
            is_auto_save: true,
            silent: true
          });
          callRuby("saveData", JSON.stringify(payload));
        }
      } catch (err) {
        console.error("AutoSave error:", err);
        updateAutoSaveIndicator("error", "Ошибка автосохранения");
      }
    }, 400);
  }

  // Notify and auto-save layout and project data
  function notifyChange() {
    try {
      if (typeof markDirty === "function") markDirty();
    } catch (err) {}
    if (window.bridge && typeof bridge.saveLayout === "function") {
      bridge.saveLayout(JSON.stringify(state.pdf_settings?.custom_layouts));
    }
    triggerAutoSave();
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
        const defLines = defSlot.lines ? deepClone(defSlot.lines) : (DEFAULT_LINES_BY_CONTENT[slotDef.id] ? deepClone(DEFAULT_LINES_BY_CONTENT[slotDef.id]) : (slotDef.default_lines ? deepClone(slotDef.default_lines) : []));
        const defLineRows = defSlot.line_rows ? deepClone(defSlot.line_rows) : (slotDef.default_line_rows ? deepClone(slotDef.default_line_rows) : null);
        const defLineFontSizes = defSlot.line_font_sizes ? deepClone(defSlot.line_font_sizes) : (slotDef.default_line_font_sizes ? deepClone(slotDef.default_line_font_sizes) : null);
        const defLineColors = defSlot.line_colors ? deepClone(defSlot.line_colors) : (slotDef.default_line_colors ? deepClone(slotDef.default_line_colors) : null);
        const defLineAligns = defSlot.line_aligns ? deepClone(defSlot.line_aligns) : (slotDef.default_line_aligns ? deepClone(slotDef.default_line_aligns) : null);
        const defLineValigns = defSlot.line_valigns ? deepClone(defSlot.line_valigns) : (slotDef.default_line_valigns ? deepClone(slotDef.default_line_valigns) : null);

        if (!current) {
          state.pdf_settings.custom_layouts[tplKey][slotDef.id] = {
            visible: defSlot.visible !== false,
            content: defContent,
            custom_text: defSlot.custom_text || "",
            align: defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left"),
            valign: defSlot.valign || (slotDef.id === "footer" ? "bottom" : (slotDef.id === "header" ? "top" : "top")),
            font_size: defFontSize,
            aspect_ratio: defSlot.aspect_ratio || slotDef.aspect_ratio || "4:3",
            scale_pct: defSlot.scale_pct !== undefined ? defSlot.scale_pct : (slotDef.scale_pct !== undefined ? slotDef.scale_pct : 100),
            lines: defLines,
            line_rows: defLineRows,
            line_font_sizes: defLineFontSizes,
            line_colors: defLineColors,
            line_aligns: defLineAligns,
            line_valigns: defLineValigns,
            opacity: defSlot.opacity !== undefined ? defSlot.opacity : 0.9
          };
        } else {
          if (current.visible === undefined) current.visible = defSlot.visible !== false;
          if (slotDef.id === "image_4_3") {
            if (!current.aspect_ratio) current.aspect_ratio = defSlot.aspect_ratio || "4:3";
            if (current.scale_pct === undefined) current.scale_pct = defSlot.scale_pct !== undefined ? defSlot.scale_pct : 100;
          }
          if (!current.content || (current.content === "none" && defSlot.content && defSlot.content !== "none" && !current.explicit_none)) {
            current.content = defContent;
          }
          if (!current.align) current.align = defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left");
          if (current.font_size === undefined) current.font_size = defFontSize;
          if (!current.lines) current.lines = defLines;
          if (slotDef.id === "header") {
            const ALLOWED_HDR_KEYS = ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"];
            if (Array.isArray(current.lines)) {
              const hasAnyAllowed = current.lines.some((k) => ALLOWED_HDR_KEYS.includes(k));
              if (!hasAnyAllowed && current.lines.length > 0) {
                current.lines = [...ALLOWED_HDR_KEYS];
              } else {
                current.lines = current.lines.filter((k) => ALLOWED_HDR_KEYS.includes(k));
              }
            }
            if (!current.valign) current.valign = defSlot.valign || "top";
            if (!current.line_rows) current.line_rows = defLineRows;
            if (!current.line_font_sizes) current.line_font_sizes = defLineFontSizes;
            if (!current.line_colors) current.line_colors = defLineColors;
          }
          if (slotDef.id === "slot_1") {
            if (!current.content) current.content = defSlot.content || "info_lines";
            if (!current.lines) {
              current.lines = defSlot.lines ? deepClone(defSlot.lines) : deepClone(DEFAULT_MIDDLE_SLOT.lines);
            }
            if (!current.line_aligns) current.line_aligns = defLineAligns ? deepClone(defLineAligns) : deepClone(DEFAULT_MIDDLE_ALIGNS);
            if (!current.line_valigns) current.line_valigns = defLineValigns ? deepClone(defLineValigns) : deepClone(DEFAULT_MIDDLE_VALIGNS);
            if (!current.line_font_sizes) current.line_font_sizes = defLineFontSizes ? deepClone(defLineFontSizes) : deepClone(DEFAULT_MIDDLE_SIZES);
            if (!current.line_colors) current.line_colors = defLineColors ? deepClone(defLineColors) : deepClone(DEFAULT_MIDDLE_COLORS);
            if (current.item_gap_mm === undefined && current.item_gap === undefined) {
              current.item_gap_mm = defSlot.item_gap_mm !== undefined ? defSlot.item_gap_mm : 2;
            }
          }
          if (slotDef.id === "footer" && !current.line_aligns) current.line_aligns = deepClone(defLineAligns);
          if (current.opacity === undefined) current.opacity = defSlot.opacity !== undefined ? defSlot.opacity : 0.9;
        }
      });
    });
  }

  function getActiveLayoutBlocks() {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate || "cover";
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
      const defaultLineValigns = defSlot.line_valigns || slotDef.default_line_valigns || null;

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
        valign: custom.valign || defSlot.valign || (slotDef.id === "footer" ? "bottom" : "top"),
        font_size: custom.font_size !== undefined ? custom.font_size : (defSlot.font_size !== undefined ? defSlot.font_size : (slotDef.id === "header" ? 11 : (slotDef.id === "footer" ? 8.5 : 8))),
        aspect_ratio: custom.aspect_ratio || defSlot.aspect_ratio || slotDef.aspect_ratio || "4:3",
        scale_pct: custom.scale_pct !== undefined ? custom.scale_pct : (defSlot.scale_pct !== undefined ? defSlot.scale_pct : (slotDef.scale_pct !== undefined ? slotDef.scale_pct : 100)),
        lines: custom.lines ? [...custom.lines] : (defSlot.lines ? [...defSlot.lines] : [...defaultLines]),
        line_rows: custom.line_rows ? Object.assign({}, custom.line_rows) : (defaultLineRows ? Object.assign({}, defaultLineRows) : null),
        line_font_sizes: custom.line_font_sizes ? Object.assign({}, custom.line_font_sizes) : (defaultLineFontSizes ? Object.assign({}, defaultLineFontSizes) : null),
        line_colors: custom.line_colors ? Object.assign({}, custom.line_colors) : (defaultLineColors ? Object.assign({}, defaultLineColors) : null),
        line_aligns: custom.line_aligns ? Object.assign({}, custom.line_aligns) : (defaultLineAligns ? Object.assign({}, defaultLineAligns) : null),
        line_valigns: custom.line_valigns ? Object.assign({}, custom.line_valigns) : (defaultLineValigns ? Object.assign({}, defaultLineValigns) : null),
        opacity: custom.opacity !== undefined ? custom.opacity : (defSlot.opacity !== undefined ? defSlot.opacity : 0.9),
        content_options: slotDef.content_options || null
      };
    });
  }

  function getBlockData(blockId) {
    const blocks = getActiveLayoutBlocks();
    return blocks.find((b) => b.id === blockId) || null;
  }

  function ensureMiddleSlotDefaults(targetTpl) {
    ensureCustomLayouts();
    const tplKey = targetTpl || layoutState.currentTemplate || "cover";
    if (!state.pdf_settings.custom_layouts[tplKey]) {
      state.pdf_settings.custom_layouts[tplKey] = {};
    }
    const defTpl = DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS.cover;
    const defSlot1 = defTpl.slots?.slot_1 || DEFAULT_MIDDLE_SLOT;
    if (!state.pdf_settings.custom_layouts[tplKey].slot_1) {
      state.pdf_settings.custom_layouts[tplKey].slot_1 = deepClone(defSlot1);
    }
    const s1 = state.pdf_settings.custom_layouts[tplKey].slot_1;
    if (!s1.content) s1.content = defSlot1.content || "info_lines";
    if (!s1.lines) {
      s1.lines = deepClone(defSlot1.lines || DEFAULT_MIDDLE_SLOT.lines);
    }
    if (!s1.line_aligns) s1.line_aligns = deepClone(defSlot1.line_aligns || DEFAULT_MIDDLE_ALIGNS);
    if (!s1.line_valigns) s1.line_valigns = deepClone(defSlot1.line_valigns || DEFAULT_MIDDLE_VALIGNS);
    if (!s1.line_font_sizes) s1.line_font_sizes = deepClone(defSlot1.line_font_sizes || DEFAULT_MIDDLE_SIZES);
    if (!s1.line_colors) s1.line_colors = deepClone(defSlot1.line_colors || DEFAULT_MIDDLE_COLORS);
    if (s1.item_gap_mm === undefined && s1.item_gap === undefined) {
      s1.item_gap_mm = defSlot1.item_gap_mm !== undefined ? defSlot1.item_gap_mm : 2;
    }
    return s1;
  }

  function updateBlockSlot(blockId, updates, targetTplKey) {
    ensureCustomLayouts();
    const tplKey = targetTplKey || layoutState.currentTemplate || "cover";
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
    if (blockId === "slot_1" || blockId === "slot_2" || blockId === "slot_3" || blockId === "slot_4") {
      const curContent = state.pdf_settings.custom_layouts[tplKey][blockId]?.content;
      if (!updates.content && (!curContent || curContent === "none")) {
        updates.content = "info_lines";
      }
    }
    Object.assign(state.pdf_settings.custom_layouts[tplKey][blockId], deepClone(updates));
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
      const ratioLabel = blk.aspect_ratio || "4:3";
      const scaleLabel = blk.scale_pct !== undefined ? blk.scale_pct : 100;
      return `
        <div class="block-image-placeholder">
          <div class="image-aspect-badge">📐 ${ratioLabel} РЕНДЕР МОДЕЛИ (${scaleLabel}%)</div>
          <div class="image-subnote">Видовой экран сцены SketchUp под текстом</div>
        </div>
      `;
    }

    // Active lines for this block
    const activeLines = Array.isArray(blk.lines)
      ? blk.lines
      : (DEFAULT_LINES_BY_CONTENT[blk.content] || []);

    if (blk.id === "header") {
      const headerValign = blk.valign || "top";
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
        return "";
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
        <div style="font-size: ${fontSize}px; color: #64748B; font-stretch: extra-condensed; letter-spacing: -0.025em; display: flex; justify-content: space-between; align-items: flex-end; width: 100%; height: 100%; overflow: hidden; white-space: nowrap; padding: 0 4px; box-sizing: border-box; gap: 8px;">
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
    const lineFontSizes = blk.line_font_sizes || {};
    const lineColors = blk.line_colors || {};
    if (activeLines.length > 0) {
      renderedLinesHtml = activeLines.map((lineKey) => {
        const lineDef = AVAILABLE_INFO_LINES.find((l) => l.key === lineKey);
        if (!lineDef) return "";
        const val = lineDef.getVal(info, wf);
        if (!val && val !== 0) return "";
        const itFs = parseFloat(lineFontSizes[lineKey]) || fontSize;
        const itCol = (lineColors[lineKey] || "#334155").trim();
        return `<div style="font-size: ${itFs}px; color: ${itCol}; line-height: 1.35;"><b>${lineDef.label}:</b> ${val}</div>`;
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
  const MIDDLE_LINE_FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16];
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

  // Синхронизация пропорций кадра и параметров оверлея в SketchUp с блоком "Картинка чертежа" шаблона
  function syncCurrentTemplateOverlay(overrideRatio) {
    const tplKey = layoutState.currentTemplate || "cover";
    ensureCustomLayouts();
    const customLayouts = state.pdf_settings ? state.pdf_settings.custom_layouts || {} : {};
    const tplCfg = customLayouts[tplKey] || {};
    const imgCfg = tplCfg.image_4_3 || {};

    let ratio = overrideRatio || imgCfg.aspect_ratio || "4:3";
    ratio = String(ratio).trim();

    const displayRatio = ratio.toLowerCase() === "page" ? "ПО ЛИСТУ" : ratio.toUpperCase();
    const tplText = document.getElementById("tplAspectOverlayText");
    if (tplText) {
      tplText.textContent = `📐 РАМКА: ${displayRatio}`;
    }
    const tplNote = document.querySelector(".tpl-image-note");
    if (tplNote) {
      tplNote.textContent = `Рамка в окне SketchUp отображает точные границы кадра для текущего шаблона с выбранными пропорциями (${displayRatio}).`;
    }

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A4").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const qualityScale = parseFloat(els.selectQuality ? els.selectQuality.value : 2.0) || 2.0;
    const baseWidth = Math.round(1200 * qualityScale);

    const borderColor = state.pdf_settings?.overlay_border_color || "#0EA5E9";
    const borderOpacity = state.pdf_settings?.overlay_border_opacity !== undefined ? parseInt(state.pdf_settings.overlay_border_opacity, 10) : 100;
    const maskColor = state.pdf_settings?.overlay_mask_color || "#0F172A";
    const maskOpacity = state.pdf_settings?.overlay_mask_opacity !== undefined ? parseInt(state.pdf_settings.overlay_mask_opacity, 10) : 55;

    const payload = {
      template_key: tplKey,
      aspect_ratio: ratio,
      image_aspect_ratio: ratio,
      custom_layouts: state.pdf_settings ? state.pdf_settings.custom_layouts : null,
      page_size: pageSize,
      page_layout: pageLayout,
      image_width: baseWidth,
      show_aspect_overlay: true,
      overlay_border_color: borderColor,
      overlay_border_opacity: borderOpacity,
      overlay_mask_color: maskColor,
      overlay_mask_opacity: maskOpacity
    };
    callRuby("updateAspectSettings", JSON.stringify(payload));
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
    const headerValign = header.valign || "top";
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

    const headerAvailableLines = [
      { key: "furniture_name", label: "🏷️ Название мебели / Изделие", preview: sampleFurn, row: rowFurn, size: sizeFurn, color: colFurn }, // data-key="furniture_name"
      { key: "place_address", label: "🚪 Место установки | 📍 Адрес объекта", preview: `${sampleRoom} | ${sampleAddr}`, row: rowPlace, size: sizePlace, color: colPlace }, // data-key="place_address"
      { key: "customer_or_company", label: "👤 Имя заказчика или 🏢 Компания", preview: sampleCust, row: rowCust, size: sizeCust, color: colCust }, // data-key="customer_or_company"
      { key: "scene_name", label: "📐 Название Сцены", preview: sampleSceneName, row: rowSceneName, size: sizeSceneName, color: colSceneName }, // data-key="scene_name"
      { key: "scene_description", label: "📝 Описание Сцены", preview: sampleSceneDesc || 'нет описания', row: rowSceneDesc, size: sizeSceneDesc, color: colSceneDesc } // data-key="scene_description"
    ];

    const savedHeaderOrder = Array.isArray(header.item_order) ? header.item_order : [];
    const orderedHeaderLines = [...headerAvailableLines].sort((a, b) => {
      let idxA = savedHeaderOrder.indexOf(a.key);
      let idxB = savedHeaderOrder.indexOf(b.key);
      if (idxA === -1 && idxB === -1) {
        return (a.row || 0) - (b.row || 0);
      }
      if (idxA === -1) return 1;
      if (idxB === -1) return -1;
      return idxA - idxB;
    });

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
              ${orderedHeaderLines.map((item) => `
                <div class="tpl-line-item tpl-hdr-line-row" draggable="true" data-key="${item.key}">
                  <span class="drag-handle" title="Перетащите мышкой для изменения порядка">⠿</span>
                  <label class="tpl-hdr-label-wrap">
                    <input type="checkbox" class="chk-hdr-line" data-key="${item.key}" ${headerLines.includes(item.key) ? 'checked' : ''}>
                    <span class="tpl-line-label">${item.label}</span>
                    <span class="tpl-line-preview">(${item.preview})</span>
                  </label>
                  ${renderHdrItemControls(item.key, item.row, item.size, item.color)}
                </div>
              `).join("")}
            </div>
          </div>
        </div>
      </div>
    `;

    // -------------------------------------------------------------
    // CARD 2: СРЕДНИЙ БЛОК (Middle)
    // -------------------------------------------------------------
    const isMiddleVis = slot1.visible !== false;
    const middleFontSize = slot1.font_size !== undefined ? parseFloat(slot1.font_size) : 8;
    const middleItemGap = slot1.item_gap_mm !== undefined ? parseFloat(slot1.item_gap_mm) : (slot1.item_gap !== undefined ? parseFloat(slot1.item_gap) : 2);
    const middleLines = Array.isArray(slot1.lines) ? slot1.lines : (DEFAULT_LINES_BY_CONTENT.slot_1 || []);
    const middleLineAligns = slot1.line_aligns || {};
    const middleLineValigns = slot1.line_valigns || {};
    const middleLineFontSizes = slot1.line_font_sizes || {};
    const middleLineColors = slot1.line_colors || {};

    const getMidAlign = (k, def = "left") => {
      const val = (middleLineAligns[k] || "").trim();
      return (val === "right" || val === "left") ? val : def;
    };
    const getMidValign = (k, def = "top") => {
      const val = (middleLineValigns[k] || "").trim();
      return (val === "bottom" || val === "center" || val === "top") ? val : def;
    };
    const getMidSize = (k, def = middleFontSize || 8) => {
      const val = parseFloat(middleLineFontSizes[k]);
      return (!isNaN(val) && val > 0) ? val : def;
    };
    const getMidColor = (k, def = "#334155") => {
      const val = (middleLineColors[k] || "").trim();
      return val || def;
    };

    const middleAvailableLines = [
      { key: "toc_pages",         label: "📑 Содержание (список страниц)", val: "1. Титул, 2. План" },
      { key: "spec_materials",    label: "🛠️ Материалы и фурнитура",      val: (info.materials || "Фасады МДФ, ЛДСП, Blum...").trim() },
      { key: "spec_appliances",   label: "🔌 Техника и подсветка",        val: [info.appliances, info.lighting].filter(Boolean).map(s => s.trim()).filter(Boolean).join("; ") || "Встраиваемая техника, LED 3000K..." },
      { key: "general_notes",     label: "📝 Общие пояснения",            val: (info.project_description || info.description || info.notes || "Замеры выполнены по факту").trim() },
      { key: "workflow_history",  label: "📜 История правок",             val: (wf.last_edit || info.last_edit || "Корректировка фасадов").trim() },
      { key: "workflow_stadia",   label: "⏱️ Стадия проекта",             val: (Array.isArray(wf.stadia) ? wf.stadia.map(st => Array.isArray(st) ? st[2] : String(st)).join(", ") : String(wf.stadia || wf.status || info.status || "РД")).trim() },
      { key: "workflow_revision", label: "🔢 Ревизия",                   val: (wf.revision || info.revision || "001").trim() },
      { key: "workflow_version",  label: "🏷️ Версия",                    val: (wf.version || info.version || "01").trim() },
      { key: "workflow_date",     label: "📅 Дата",                      val: (wf.date_order || info.date || new Date().toISOString().slice(0, 10)).trim() },
      { key: "articul",           label: "🔖 Артикул проекта",           val: (info.articul || "CF#...").trim() }
    ];

    const renderMiddleItemControls = (key, activeAlign, activeValign, activeSize, activeColor) => {
      let sizeOptions = "";
      let matched = false;
      const roundedSize = Math.round(activeSize);
      MIDDLE_LINE_FONT_SIZES.forEach((sz) => {
        const isSel = (roundedSize === sz);
        if (isSel) matched = true;
        sizeOptions += `<option value="${sz}" ${isSel ? 'selected' : ''}>${sz} pt</option>`;
      });
      if (!matched && activeSize) {
        sizeOptions += `<option value="${activeSize}" selected>${activeSize} pt</option>`;
      }

      return `
        <div class="tpl-middle-item-controls" data-key="${key}">
          <div class="tpl-btn-group tpl-middle-edge-group" data-key="${key}" title="Край страницы: слева / справа">
            <button type="button" class="tpl-btn-align tpl-btn-middle-edge ${activeAlign === 'left' ? 'active' : ''}" data-key="${key}" data-align="left" title="По левому краю страницы">⇤</button>
            <button type="button" class="tpl-btn-align tpl-btn-middle-edge ${activeAlign === 'right' ? 'active' : ''}" data-key="${key}" data-align="right" title="По правому краю страницы">⇥</button>
          </div>
          <div class="tpl-btn-group tpl-middle-valign-group" data-key="${key}" title="По высоте: сверху / середина / снизу">
            <button type="button" class="tpl-btn-align tpl-btn-middle-valign ${activeValign === 'top' ? 'active' : ''}" data-key="${key}" data-valign="top" title="Сверху">⬆</button>
            <button type="button" class="tpl-btn-align tpl-btn-middle-valign ${activeValign === 'center' ? 'active' : ''}" data-key="${key}" data-valign="center" title="По центру (середина)">↕</button>
            <button type="button" class="tpl-btn-align tpl-btn-middle-valign ${activeValign === 'bottom' ? 'active' : ''}" data-key="${key}" data-valign="bottom" title="Снизу">⬇</button>
          </div>
          <div class="tpl-hdr-param-box tpl-middle-param-size" title="Размер шрифта строки (пт)">
            <select class="tpl-hdr-select sel-middle-line-size" data-key="${key}">
              ${sizeOptions}
            </select>
          </div>
          <div class="tpl-hdr-param-box tpl-middle-param-color" title="Цвет текста строки">
            <input type="color" class="inp-hdr-line-color inp-middle-line-color" data-key="${key}" value="${activeColor || '#334155'}" title="Цвет текста">
          </div>
        </div>
      `;
    };

    const savedMiddleOrder = Array.isArray(slot1.item_order) ? slot1.item_order : [];
    const orderedMiddleLines = [...middleAvailableLines].sort((a, b) => {
      let idxA = savedMiddleOrder.indexOf(a.key);
      let idxB = savedMiddleOrder.indexOf(b.key);
      if (idxA === -1 && idxB === -1) return 0;
      if (idxA === -1) return 1;
      if (idxB === -1) return -1;
      return idxA - idxB;
    });

    const cardMiddleHtml = `
      <div class="tpl-card tpl-panel-left ${!isMiddleVis ? 'disabled-card disabled-block' : ''}" id="card_middle" data-slot="slot_1">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">📋</span>
            <span class="tpl-card-title">Средний блок</span>
          </div>
          <div class="tpl-card-header-actions">
            <div class="tpl-footer-font-control">
              <span class="tpl-footer-font-label">Шрифт:</span>
              <select class="form-control tpl-control-select sel-slot-fontsize" data-slot="slot_1">
                ${renderFontSizeOptions(middleFontSize, MIDDLE_LINE_FONT_SIZES, 8)}
              </select>
            </div>
            <div class="tpl-footer-font-control" title="Расстояние между пунктами на странице">
              <span class="tpl-footer-font-label" title="Расстояние между пунктами на странице">Расстояние:</span>
              <input type="number" class="form-control tpl-control-input inp-slot-itemgap" data-slot="slot_1" min="0" max="30" step="0.5" value="${middleItemGap}" style="width: 44px;" title="Расстояние между пунктами на странице (мм)">
              <span class="unit-text" style="font-size: 10px; color: #64748b; font-weight: 600;">мм</span>
            </div>
            <div style="display: flex; gap: 3px; margin-right: 4px;">
              <button type="button" class="btn btn-xs btn-secondary btn-slot-all" data-slot="slot_1" style="font-size: 9px; padding: 1px 5px;">Все</button>
              <button type="button" class="btn btn-xs btn-secondary btn-slot-none" data-slot="slot_1" style="font-size: 9px; padding: 1px 5px;">Снять</button>
            </div>
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin-left: 4px;">
              <input type="checkbox" class="chk-slot-visible" data-slot="slot_1" ${isMiddleVis ? 'checked' : ''}>
              <span>Вкл</span>
            </label>
          </div>
        </div>
        <div class="tpl-card-body">
          <div>
            <div class="tpl-middle-columns-header">
              <span class="tpl-middle-col-title-lines">Выводимые строки среднего блока:</span>
              <div class="tpl-middle-col-titles">
                <span class="tpl-middle-col-title col-edge" title="Выравнивание: по левому / правому краю страницы">⇤ / ⇥</span>
                <span class="tpl-middle-col-title col-valign" title="По высоте: сверху / середина / снизу">⬆ ↕ ⬇</span>
                <span class="tpl-middle-col-title col-size" title="Размер шрифта (пт)">Aa</span>
                <span class="tpl-middle-col-title col-color" title="Цвет текста">🎨</span>
              </div>
            </div>
            <div class="tpl-lines-checklist">
              ${orderedMiddleLines.map(item => {
                const align = getMidAlign(item.key, "left");
                const valign = getMidValign(item.key, "top");
                const size = getMidSize(item.key, middleFontSize);
                const color = getMidColor(item.key, "#334155");
                const isChecked = middleLines.includes(item.key);
                return `
                  <div class="tpl-line-item tpl-middle-line-row" draggable="true" data-key="${item.key}">
                    <span class="drag-handle" title="Перетащите мышкой для изменения порядка">⠿</span>
                    <label class="tpl-middle-label-wrap">
                      <input type="checkbox" class="chk-slot-line" data-slot="slot_1" data-key="${item.key}" ${isChecked ? 'checked' : ''}>
                      <span class="tpl-line-label">${item.label}</span>
                      ${item.val ? `<span class="tpl-line-preview">(${item.val})</span>` : ''}
                    </label>
                    ${renderMiddleItemControls(item.key, align, valign, size, color)}
                  </div>
                `;
              }).join("")}
            </div>
          </div>
        </div>
      </div>
    `;

    // -------------------------------------------------------------
    // CARD 3: ПОДВАЛ СТРАНИЦЫ (Footer)
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

    const savedFooterOrder = Array.isArray(footer.item_order) ? footer.item_order : [];
    const orderedFooterLines = [...footerItemsDef].sort((a, b) => {
      let idxA = savedFooterOrder.indexOf(a.key);
      let idxB = savedFooterOrder.indexOf(b.key);
      if (idxA === -1 && idxB === -1) return 0;
      if (idxA === -1) return 1;
      if (idxB === -1) return -1;
      return idxA - idxB;
    });

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
            <div class="tpl-ftr-columns-header">
              <span>Выводимые секции подвала:</span>
              <span style="font-size: 10px; color: #64748b; font-weight: 600;">Выравнивание: слева / центр / справа • По нижнему краю страницы ⬇</span>
            </div>
            <div class="tpl-lines-checklist">
              ${orderedFooterLines.map((item) => {
                const isChecked = effectiveFooterLines.includes(item.key);
                const curAlign = footerLineAligns[item.key] || defaultFooterAligns[item.key] || "center";
                return `
                  <div class="tpl-line-item tpl-ftr-line-row" draggable="true" data-key="${item.key}">
                    <span class="drag-handle" title="Перетащите мышкой для изменения порядка">⠿</span>
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
    // CARD 4: КАРТИНКА ЧЕРТЕЖА ПОД ТЕКСТ (Drawing Viewport)
    // -------------------------------------------------------------
    const isImageVis = image43.visible !== false;
    const imageAspectRatio = (image43.aspect_ratio || "4:3").trim();
    const displayAspect = imageAspectRatio.toLowerCase() === "page" ? "ПО ЛИСТУ" : imageAspectRatio.toUpperCase();
    const imageScalePct = parseInt(image43.scale_pct !== undefined ? image43.scale_pct : 100, 10) || 100;
    const isOverlayOn = Boolean(state.pdf_settings && state.pdf_settings.show_aspect_overlay);
    const rawBorderColor = (state.pdf_settings && state.pdf_settings.overlay_border_color) || "#0EA5E9";
    const overlayBorderColor = rawBorderColor.startsWith("#") ? rawBorderColor : `#${rawBorderColor}`;
    const overlayBorderOpacity = state.pdf_settings && state.pdf_settings.overlay_border_opacity !== undefined ? parseInt(state.pdf_settings.overlay_border_opacity, 10) : 100;
    const rawMaskColor = (state.pdf_settings && state.pdf_settings.overlay_mask_color) || "#0F172A";
    const overlayMaskColor = rawMaskColor.startsWith("#") ? rawMaskColor : `#${rawMaskColor}`;
    const overlayMaskOpacity = state.pdf_settings && state.pdf_settings.overlay_mask_opacity !== undefined ? parseInt(state.pdf_settings.overlay_mask_opacity, 10) : 55;

    const cardImageHtml = `
      <div class="tpl-card tpl-panel-left ${!isImageVis ? 'disabled-card disabled-block' : ''}" id="card_image">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">🖼️</span>
            <span class="tpl-card-title">Картинка чертежа под текст (Видовой экран 3D)</span>
          </div>
          <div class="tpl-card-header-actions">
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer;">
              <input type="checkbox" id="chk_image_4_3_visible" ${isImageVis ? 'checked' : ''}>
              <span>Вкл</span>
            </label>
          </div>
        </div>
        <div class="tpl-card-body">
          <div class="tpl-image-controls-row">
            <div class="tpl-control-item">
              <span class="tpl-control-label">Пропорции картинки:</span>
              <div class="tpl-btn-group" id="grp_image_aspect_ratio">
                <button type="button" class="tpl-btn-align btn-aspect-ratio ${imageAspectRatio === '3:2' ? 'active' : ''}" data-ratio="3:2" title="Пропорция 3:2 (фотокадр)">3:2</button>
                <button type="button" class="tpl-btn-align btn-aspect-ratio ${imageAspectRatio === '4:3' ? 'active' : ''}" data-ratio="4:3" title="Пропорция 4:3 (стандарт)">4:3</button>
                <button type="button" class="tpl-btn-align btn-aspect-ratio ${imageAspectRatio === '16:9' ? 'active' : ''}" data-ratio="16:9" title="Пропорция 16:9 (широкоформатный)">16:9</button>
                <button type="button" class="tpl-btn-align btn-aspect-ratio ${imageAspectRatio === '1:1' ? 'active' : ''}" data-ratio="1:1" title="Пропорция 1:1 (квадрат)">1:1</button>
                <button type="button" class="tpl-btn-align btn-aspect-ratio ${imageAspectRatio === 'page' ? 'active' : ''}" data-ratio="page" title="По пропорциям страницы листа">По листу</button>
              </div>
            </div>
            <div class="tpl-control-item">
              <span class="tpl-control-label">Размещение на странице:</span>
              <div class="tpl-btn-group" id="grp_image_scale_pct">
                <button type="button" class="tpl-btn-align btn-scale-pct ${imageScalePct === 60 ? 'active' : ''}" data-scale="60" title="60% от размера листа">60%</button>
                <button type="button" class="tpl-btn-align btn-scale-pct ${imageScalePct === 70 ? 'active' : ''}" data-scale="70" title="70% от размера листа">70%</button>
                <button type="button" class="tpl-btn-align btn-scale-pct ${imageScalePct === 80 ? 'active' : ''}" data-scale="80" title="80% от размера листа">80%</button>
                <button type="button" class="tpl-btn-align btn-scale-pct ${imageScalePct === 90 ? 'active' : ''}" data-scale="90" title="90% от размера листа">90%</button>
                <button type="button" class="tpl-btn-align btn-scale-pct ${imageScalePct === 100 ? 'active' : ''}" data-scale="100" title="100% (во весь лист)">100%</button>
              </div>
            </div>
            <label class="checkbox-label tpl-overlay-toggle-label ${isOverlayOn ? '' : 'disabled-overlay'}" id="tplAspectOverlayBadge" title="Отображать рамку кадра в окне SketchUp (Safe Frame Overlay)" style="margin-left: auto;">
              <input type="checkbox" id="chk_tpl_aspect_overlay" ${isOverlayOn ? 'checked' : ''} style="cursor: pointer; margin: 0;">
              <span id="tplAspectOverlayText">📐 РАМКА: ${displayAspect}</span>
            </label>
          </div>

          <div class="tpl-overlay-styling-row">
            <div class="tpl-overlay-style-item" title="Цвет контурной рамки в окне SketchUp">
              <span class="tpl-overlay-style-label">Цвет рамки:</span>
              <div class="tpl-color-picker-wrap">
                <input type="color" id="input_overlay_border_color" value="${overlayBorderColor}" class="tpl-color-picker">
                <span class="tpl-color-hex" id="val_overlay_border_color">${overlayBorderColor}</span>
              </div>
            </div>

            <div class="tpl-overlay-style-item" title="Прозрачность контурной рамки (10% - 100%)">
              <span class="tpl-overlay-style-label">Прозрачность рамки:</span>
              <div class="tpl-range-wrap">
                <input type="range" min="10" max="100" step="5" id="input_overlay_border_opacity" value="${overlayBorderOpacity}" class="tpl-range-slider">
                <span class="tpl-range-val" id="val_overlay_border_opacity">${overlayBorderOpacity}%</span>
              </div>
            </div>

            <div class="tpl-overlay-style-item" title="Цвет затемнения вне кадра">
              <span class="tpl-overlay-style-label">Цвет затемнения:</span>
              <div class="tpl-color-picker-wrap">
                <input type="color" id="input_overlay_mask_color" value="${overlayMaskColor}" class="tpl-color-picker">
                <span class="tpl-color-hex" id="val_overlay_mask_color">${overlayMaskColor}</span>
              </div>
            </div>

            <div class="tpl-overlay-style-item" title="Степень затемнения вне кадра (0% - 100%)">
              <span class="tpl-overlay-style-label">Затемнение:</span>
              <div class="tpl-range-wrap">
                <input type="range" min="0" max="100" step="5" id="input_overlay_mask_opacity" value="${overlayMaskOpacity}" class="tpl-range-slider">
                <span class="tpl-range-val" id="val_overlay_mask_opacity">${overlayMaskOpacity}%</span>
              </div>
            </div>
          </div>

          <p class="tpl-image-note">
            Рамка в окне SketchUp отображает точные границы кадра для текущего шаблона с выбранными пропорциями (${displayAspect}).
          </p>
        </div>
      </div>
    `;

    // -------------------------------------------------------------
    // FULL TWO-COLUMN ASSEMBLY REPLACED BY SINGLE COLUMN (Заголовок, Средний, Подвал, Картинка)
    // -------------------------------------------------------------
    html = `
      <div class="tpl-single-column-layout">
        ${cardHeaderHtml}
        ${cardMiddleHtml}
        ${cardFooterHtml}
        ${cardImageHtml}
      </div>
    `;

    els.templateSettingsContainer.innerHTML = html;
    bindTemplateSettingsEvents(tplKey);
    syncCurrentTemplateOverlay();
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
          ? `<div class="tpl-control-item" title="Ширина блока в % от правого края листа"><span style="font-size: 10px; color: #64748b;">% от края</span><input type="number" class="form-control tpl-control-input inp-slot-col-w" data-side="right" min="10" max="80" step="1" value="${widthPct}" style="width: 44px; height: 21px;"><span class="tpl-control-label">:Ширина</span></div>`
          : `<div class="tpl-control-item" title="Ширина блока в % от левого края листа"><span class="tpl-control-label">Ширина:</span><input type="number" class="form-control tpl-control-input inp-slot-col-w" data-side="left" min="10" max="80" step="1" value="${widthPct}" style="width: 44px; height: 21px;"><span style="font-size: 10px; color: #64748b;">% от края</span></div>`)
      : "";

    const isBottomSlot = (slotId === "slot_2" || slotId === "slot_4");
    const alignBadgeHtml = isRight
      ? `<span class="badge" style="font-size: 9px; background: #f1f5f9; color: #334155; padding: 1px 5px; font-weight: 600; border: none;" title="Текст на странице PDF выравнивается ${isBottomSlot ? 'от низа и ' : ''}по правому краю">${isBottomSlot ? 'От низа ⬇ • ' : ''}Текст справа ➡</span>`
      : `<span class="badge" style="font-size: 9px; background: #e0f2fe; color: #0369a1; padding: 1px 5px; font-weight: 600; border: none;" title="Текст на странице PDF выравнивается ${isBottomSlot ? 'от низа и ' : ''}по левому краю">⬅ Текст слева${isBottomSlot ? ' • От низа ⬇' : ''}</span>`;

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
              <div style="margin-left: auto; display: flex; gap: 3px;">
                <button type="button" class="btn btn-xs btn-secondary btn-slot-all" data-slot="${slotId}" style="font-size: 9px; padding: 1px 5px;">Все</button>
                <button type="button" class="btn btn-xs btn-secondary btn-slot-none" data-slot="${slotId}" style="font-size: 9px; padding: 1px 5px;">Снять</button>
              </div>
            ` : `
              <div style="margin-right: auto; display: flex; gap: 3px;">
                <button type="button" class="btn btn-xs btn-secondary btn-slot-all" data-slot="${slotId}" style="font-size: 9px; padding: 1px 5px;">Все</button>
                <button type="button" class="btn btn-xs btn-secondary btn-slot-none" data-slot="${slotId}" style="font-size: 9px; padding: 1px 5px;">Снять</button>
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
            <div class="tpl-slot-lines-title" style="text-align: ${textAlign};">Выводимые строки блока:</div>
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

    // Header Visible Toggle
    const chkHdrVis = document.getElementById("chk_header_visible");
    if (chkHdrVis) {
      chkHdrVis.addEventListener("change", (e) => {
        updateBlockSlot("header", { visible: e.target.checked }, tplKey);
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
          updateBlockSlot("header", { valign: btn.dataset.valign, align: "center" }, tplKey);
          notifyChange();
        });
      });
    }

    // Header Lines Checkboxes
    const hdrCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-hdr-line");
    hdrCheckboxes.forEach((chk) => {
      chk.addEventListener("change", () => {
        const checkedKeys = Array.from(els.templateSettingsContainer.querySelectorAll(".chk-hdr-line"))
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        updateBlockSlot("header", { lines: checkedKeys }, tplKey);
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
          updateBlockSlot("header", { lines: checkedKeys, line_rows: currentLineRows }, tplKey);
        } else {
          updateBlockSlot("header", { line_rows: currentLineRows }, tplKey);
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
          updateBlockSlot("header", { lines: checkedKeys, line_font_sizes: currentLineSizes }, tplKey);
        } else {
          updateBlockSlot("header", { line_font_sizes: currentLineSizes }, tplKey);
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
          updateBlockSlot("header", { lines: checkedKeys, line_colors: currentLineColors }, tplKey);
        } else {
          updateBlockSlot("header", { line_colors: currentLineColors }, tplKey);
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
          updateBlockSlot("header", { lines: checkedKeys, line_rows: currentLineRows }, tplKey);
        } else {
          updateBlockSlot("header", { line_rows: currentLineRows }, tplKey);
        }
        notifyChange();
      });
    });



    // Slot Visibility Toggles
    const slotVisCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-slot-visible");
    slotVisCheckboxes.forEach((chk) => {
      chk.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot;
        const updates = { visible: e.target.checked };
        if (e.target.checked && (sId === "slot_1" || sId === "slot_2" || sId === "slot_3" || sId === "slot_4")) {
          updates.content = "info_lines";
        }
        updateBlockSlot(sId, updates, tplKey);
        const blk = (sId === "slot_1" ? document.getElementById("card_middle") : null) || document.getElementById(`block_${sId}`) || document.getElementById("card_middle");
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
        const newFs = parseFloat(e.target.value);
        if (sId === "slot_1") {
          const targetTpl = tplKey || layoutState.currentTemplate || "cover";
          const s1 = ensureMiddleSlotDefaults(targetTpl);
          s1.font_size = newFs;
          if (!s1.line_font_sizes) s1.line_font_sizes = {};
          const allMidKeys = [
            "toc_pages", "spec_materials", "spec_appliances", "general_notes",
            "workflow_history", "workflow_stadia", "workflow_revision",
            "workflow_version", "workflow_date", "articul"
          ];
          allMidKeys.forEach((k) => {
            s1.line_font_sizes[k] = newFs;
          });
          Object.keys(s1.line_font_sizes).forEach((k) => {
            s1.line_font_sizes[k] = newFs;
          });
          const midSelects = els.templateSettingsContainer.querySelectorAll(".sel-middle-line-size");
          midSelects.forEach((midSel) => {
            midSel.value = newFs.toString();
          });
          updateBlockSlot(sId, { font_size: newFs, line_font_sizes: s1.line_font_sizes, content: "info_lines" }, tplKey);
        } else {
          updateBlockSlot(sId, { font_size: newFs }, tplKey);
        }
        notifyChange();
      });
    });

    // Slot Item Gap (Distance between items on page) Inputs
    const slotGapInputs = els.templateSettingsContainer.querySelectorAll(".inp-slot-itemgap");
    slotGapInputs.forEach((inp) => {
      const handleGapChange = (e) => {
        const sId = e.target.dataset.slot || "slot_1";
        const val = parseFloat(e.target.value);
        const newGap = (!isNaN(val) && val >= 0) ? Math.round(val * 10) / 10 : 2;
        if (sId === "slot_1") {
          const targetTpl = tplKey || layoutState.currentTemplate || "cover";
          const s1 = ensureMiddleSlotDefaults(targetTpl);
          s1.item_gap_mm = newGap;
          s1.item_gap = newGap;
          updateBlockSlot(sId, { item_gap_mm: newGap, item_gap: newGap, content: "info_lines" }, tplKey);
        } else {
          updateBlockSlot(sId, { item_gap_mm: newGap, item_gap: newGap }, tplKey);
        }
        notifyChange();
      };
      inp.addEventListener("change", handleGapChange);
      inp.addEventListener("input", handleGapChange);
    });

    // Slot Lines Checkboxes
    const slotLineCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-slot-line");
    slotLineCheckboxes.forEach((chk) => {
      chk.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot;
        const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll(`.chk-slot-line[data-slot="${sId}"]`))
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        const updates = { lines: allSlotLines };
        if (sId === "slot_1" || sId === "slot_2" || sId === "slot_3" || sId === "slot_4") {
          updates.content = "info_lines";
        }
        updateBlockSlot(sId, updates, tplKey);
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
        const updates = { lines: keys };
        if (sId === "slot_1" || sId === "slot_2" || sId === "slot_3" || sId === "slot_4") {
          updates.content = "info_lines";
        }
        updateBlockSlot(sId, updates, tplKey);
        notifyChange();
      });
    });

    const btnSlotNone = els.templateSettingsContainer.querySelectorAll(".btn-slot-none");
    btnSlotNone.forEach((btn) => {
      btn.addEventListener("click", () => {
        const sId = btn.dataset.slot;
        const checks = els.templateSettingsContainer.querySelectorAll(`.chk-slot-line[data-slot="${sId}"]`);
        checks.forEach((c) => (c.checked = false));
        updateBlockSlot(sId, { lines: [] }, tplKey);
        notifyChange();
      });
    });

    // Middle Block Line Edge Alignment (⇤ / ⇥)
    const midEdgeBtns = els.templateSettingsContainer.querySelectorAll(".tpl-btn-middle-edge");
    midEdgeBtns.forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const key = btn.dataset.key;
        const align = btn.dataset.align;
        if (!key || !align) return;

        const group = btn.closest(".tpl-middle-edge-group");
        if (group) {
          group.querySelectorAll(".tpl-btn-middle-edge").forEach((b) => b.classList.remove("active"));
        }
        btn.classList.add("active");

        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const s1 = ensureMiddleSlotDefaults(targetTpl);
        s1.line_aligns[key] = align;

        const chk = els.templateSettingsContainer.querySelector(`.chk-slot-line[data-slot="slot_1"][data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll('.chk-slot-line[data-slot="slot_1"]'))
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          s1.lines = allSlotLines;
          s1.content = "info_lines";
          s1.visible = true;
        }
        notifyChange();
      });
    });

    // Middle Block Line Vertical Placement (⬆ / ↕ / ⬇)
    const midValignBtns = els.templateSettingsContainer.querySelectorAll(".tpl-btn-middle-valign");
    midValignBtns.forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const key = btn.dataset.key;
        const valign = btn.dataset.valign;
        if (!key || !valign) return;

        const group = btn.closest(".tpl-middle-valign-group");
        if (group) {
          group.querySelectorAll(".tpl-btn-middle-valign").forEach((b) => b.classList.remove("active"));
        }
        btn.classList.add("active");

        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const s1 = ensureMiddleSlotDefaults(targetTpl);
        s1.line_valigns[key] = valign;

        const chk = els.templateSettingsContainer.querySelector(`.chk-slot-line[data-slot="slot_1"][data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll('.chk-slot-line[data-slot="slot_1"]'))
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          s1.lines = allSlotLines;
          s1.content = "info_lines";
          s1.visible = true;
        }
        notifyChange();
      });
    });

    // Middle Block Line Font Size Selection (Dropdown)
    const midSizeSelects = els.templateSettingsContainer.querySelectorAll(".sel-middle-line-size");
    midSizeSelects.forEach((sel) => {
      sel.addEventListener("change", () => {
        const key = sel.dataset.key;
        const sz = parseFloat(sel.value);
        if (!key || isNaN(sz)) return;

        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const s1 = ensureMiddleSlotDefaults(targetTpl);
        s1.line_font_sizes[key] = sz;

        const chk = els.templateSettingsContainer.querySelector(`.chk-slot-line[data-slot="slot_1"][data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll('.chk-slot-line[data-slot="slot_1"]'))
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          s1.lines = allSlotLines;
          s1.content = "info_lines";
          s1.visible = true;
        }
        notifyChange();
      });
    });

    // Middle Block Line Color Picker (<input type="color">)
    const midColorInputs = els.templateSettingsContainer.querySelectorAll(".inp-middle-line-color");
    midColorInputs.forEach((inp) => {
      const handleColorChange = () => {
        const key = inp.dataset.key;
        const col = inp.value;
        if (!key || !col) return;

        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const s1 = ensureMiddleSlotDefaults(targetTpl);
        s1.line_colors[key] = col;

        const chk = els.templateSettingsContainer.querySelector(`.chk-slot-line[data-slot="slot_1"][data-key="${key}"]`);
        if (chk && !chk.checked) {
          chk.checked = true;
          const allSlotLines = Array.from(els.templateSettingsContainer.querySelectorAll('.chk-slot-line[data-slot="slot_1"]'))
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          s1.lines = allSlotLines;
          s1.content = "info_lines";
          s1.visible = true;
        }
        notifyChange();
      };
      inp.addEventListener("input", handleColorChange);
      inp.addEventListener("change", handleColorChange);
    });

    // Footer Visible Toggle
    const chkFtrVis = document.getElementById("chk_footer_visible");
    if (chkFtrVis) {
      chkFtrVis.addEventListener("change", (e) => {
        updateBlockSlot("footer", { visible: e.target.checked }, tplKey);
        const card = document.getElementById("card_footer");
        if (card) card.classList.toggle("disabled-card", !e.target.checked);
        notifyChange();
      });
    }

    // Footer Font Size
    const selFtrFs = document.getElementById("sel_footer_fontsize");
    if (selFtrFs) {
      selFtrFs.addEventListener("change", (e) => {
        updateBlockSlot("footer", { font_size: parseFloat(e.target.value) }, tplKey);
        notifyChange();
      });
    }

    // Footer Lines Checkboxes
    const ftrCheckboxes = els.templateSettingsContainer.querySelectorAll(".chk-ftr-line");
    ftrCheckboxes.forEach((chk) => {
      chk.addEventListener("change", () => {
        const checkedKeys = Array.from(els.templateSettingsContainer.querySelectorAll(".chk-ftr-line"))
          .filter((c) => c.checked)
          .map((c) => c.dataset.key);
        updateBlockSlot("footer", { lines: checkedKeys }, tplKey);
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
          const checkedKeys = Array.from(els.templateSettingsContainer.querySelectorAll(".chk-ftr-line"))
            .filter((c) => c.checked)
            .map((c) => c.dataset.key);
          updateBlockSlot("footer", { lines: checkedKeys, line_aligns: currentLineAligns }, tplKey);
        } else {
          updateBlockSlot("footer", { line_aligns: currentLineAligns }, tplKey);
        }
        notifyChange();
      });
    });

    // -------------------------------------------------------------
    // CARD 4: КАРТИНКА ЧЕРТЕЖА (Видовой экран 3D) EVENT LISTENERS
    // -------------------------------------------------------------
    const chkTplOverlay = document.getElementById("chk_tpl_aspect_overlay");
    if (chkTplOverlay) {
      chkTplOverlay.addEventListener("change", (e) => {
        const isChecked = e.target.checked;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.show_aspect_overlay = isChecked;
        if (els.chkShowAspectOverlay) {
          els.chkShowAspectOverlay.checked = isChecked;
        }
        const tplBadge = document.getElementById("tplAspectOverlayBadge");
        if (tplBadge) {
          tplBadge.classList.toggle("disabled-overlay", !isChecked);
        }
        callRuby("toggleAspectOverlay", isChecked);
        if (isChecked) {
          syncCurrentTemplateOverlay();
        }
      });
    }

    const chkImgVis = document.getElementById("chk_image_4_3_visible");
    if (chkImgVis) {
      chkImgVis.addEventListener("change", (e) => {
        updateBlockSlot("image_4_3", { visible: e.target.checked }, tplKey);
        const card = document.getElementById("card_image");
        if (card) {
          card.classList.toggle("disabled-card", !e.target.checked);
          card.classList.toggle("disabled-block", !e.target.checked);
        }
        notifyChange();
      });
    }

    const grpRatio = document.getElementById("grp_image_aspect_ratio");
    if (grpRatio) {
      grpRatio.querySelectorAll(".btn-aspect-ratio").forEach((btn) => {
        btn.addEventListener("click", () => {
          window.app.setAspectRatio(btn.dataset.ratio);
        });
      });
    }

    const grpScale = document.getElementById("grp_image_scale_pct");
    if (grpScale) {
      grpScale.querySelectorAll(".btn-scale-pct").forEach((btn) => {
        btn.addEventListener("click", () => {
          grpScale.querySelectorAll(".btn-scale-pct").forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          const scale = parseInt(btn.dataset.scale, 10) || 100;
          updateBlockSlot("image_4_3", { scale_pct: scale });
          notifyChange();
        });
      });
    }

    const inpBorderColor = document.getElementById("input_overlay_border_color");
    if (inpBorderColor) {
      const onBorderColorChange = (e) => {
        const val = e.target.value.toUpperCase();
        const lbl = document.getElementById("val_overlay_border_color");
        if (lbl) lbl.textContent = val;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_border_color = val;
        if (els.inputOverlayBorderColor) els.inputOverlayBorderColor.value = val;
        if (els.overlayBorderColorHex) els.overlayBorderColorHex.textContent = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      inpBorderColor.addEventListener("input", onBorderColorChange);
      inpBorderColor.addEventListener("change", onBorderColorChange);
    }

    const inpBorderOpacity = document.getElementById("input_overlay_border_opacity");
    if (inpBorderOpacity) {
      const onBorderOpacityChange = (e) => {
        const val = parseInt(e.target.value, 10) || 100;
        const lbl = document.getElementById("val_overlay_border_opacity");
        if (lbl) lbl.textContent = `${val}%`;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_border_opacity = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      inpBorderOpacity.addEventListener("input", onBorderOpacityChange);
      inpBorderOpacity.addEventListener("change", onBorderOpacityChange);
    }

    const inpMaskColor = document.getElementById("input_overlay_mask_color");
    if (inpMaskColor) {
      const onMaskColorChange = (e) => {
        const val = e.target.value.toUpperCase();
        const lbl = document.getElementById("val_overlay_mask_color");
        if (lbl) lbl.textContent = val;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_mask_color = val;
        if (els.inputOverlayMaskColor) els.inputOverlayMaskColor.value = val;
        if (els.overlayMaskColorHex) els.overlayMaskColorHex.textContent = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      inpMaskColor.addEventListener("input", onMaskColorChange);
      inpMaskColor.addEventListener("change", onMaskColorChange);
    }

    const inpMaskOpacity = document.getElementById("input_overlay_mask_opacity");
    if (inpMaskOpacity) {
      const onMaskOpacityChange = (e) => {
        const val = parseInt(e.target.value, 10) || 55;
        const lbl = document.getElementById("val_overlay_mask_opacity");
        if (lbl) lbl.textContent = `${val}%`;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_mask_opacity = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      inpMaskOpacity.addEventListener("input", onMaskOpacityChange);
      inpMaskOpacity.addEventListener("change", onMaskOpacityChange);
    }

    // =============================================================
    // DRAG AND DROP REORDERING ДЛЯ ПУНКТОВ БЛОКОВ
    // =============================================================
    function setupBlockDragAndDrop(cardElement, rowSelector, onReorder) {
      if (!cardElement) return;
      const listContainer = cardElement.querySelector(".tpl-lines-checklist");
      if (!listContainer) return;

      let draggedItem = null;

      const rows = listContainer.querySelectorAll(rowSelector);
      rows.forEach((row) => {
        row.setAttribute("draggable", "true");

        row.addEventListener("mousedown", (e) => {
          if (e.target.closest(".drag-handle")) {
            row.setAttribute("draggable", "true");
            return;
          }
          if (e.target.closest("input, select, button, label, .tpl-btn-group, .tpl-hdr-param-box")) {
            row.setAttribute("draggable", "false");
          } else {
            row.setAttribute("draggable", "true");
          }
        });

        row.addEventListener("mouseup", () => {
          row.setAttribute("draggable", "true");
        });

        row.addEventListener("dragstart", (e) => {
          draggedItem = row;
          row.classList.add("dragging");
          e.dataTransfer.effectAllowed = "move";
          e.dataTransfer.setData("text/plain", row.dataset.key || "");
        });

        row.addEventListener("dragend", () => {
          if (draggedItem) {
            draggedItem.classList.remove("dragging");
            draggedItem = null;
          }
          listContainer.querySelectorAll(rowSelector).forEach((r) => {
            r.classList.remove("drag-over-top", "drag-over-bottom");
          });
        });

        row.addEventListener("dragover", (e) => {
          e.preventDefault();
          e.dataTransfer.dropEffect = "move";
          if (!draggedItem || draggedItem === row) return;

          const rect = row.getBoundingClientRect();
          const midY = rect.top + rect.height / 2;
          if (e.clientY < midY) {
            row.classList.add("drag-over-top");
            row.classList.remove("drag-over-bottom");
          } else {
            row.classList.add("drag-over-bottom");
            row.classList.remove("drag-over-top");
          }
        });

        row.addEventListener("dragleave", () => {
          row.classList.remove("drag-over-top", "drag-over-bottom");
        });

        row.addEventListener("drop", (e) => {
          e.preventDefault();
          e.stopPropagation();
          row.classList.remove("drag-over-top", "drag-over-bottom");
          if (!draggedItem || draggedItem === row) return;

          const rect = row.getBoundingClientRect();
          const midY = rect.top + rect.height / 2;
          if (e.clientY < midY) {
            listContainer.insertBefore(draggedItem, row);
          } else {
            listContainer.insertBefore(draggedItem, row.nextSibling);
          }

          const newOrder = Array.from(listContainer.querySelectorAll(rowSelector))
            .map((r) => r.dataset.key)
            .filter(Boolean);

          if (typeof onReorder === "function") {
            onReorder(newOrder, listContainer);
          }
        });
      });
    }

    // 1. Drag and Drop для шапки (Header)
    const cardHeader = document.getElementById("card_header");
    setupBlockDragAndDrop(cardHeader, ".tpl-hdr-line-row", (newOrder, container) => {
      const targetTpl = tplKey || layoutState.currentTemplate || "cover";
      if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
      if (!state.pdf_settings.custom_layouts[targetTpl]) state.pdf_settings.custom_layouts[targetTpl] = {};
      if (!state.pdf_settings.custom_layouts[targetTpl].header) state.pdf_settings.custom_layouts[targetTpl].header = {};
      const hdrConfig = state.pdf_settings.custom_layouts[targetTpl].header;
      hdrConfig.item_order = newOrder;

      const checkedKeys = new Set(
        Array.from(container.querySelectorAll(".chk-hdr-line:checked")).map((c) => c.dataset.key)
      );
      hdrConfig.lines = newOrder.filter((k) => checkedKeys.has(k));

      const lineRows = Object.assign({}, hdrConfig.line_rows || {});
      newOrder.forEach((k, idx) => {
        const rowNum = idx + 1;
        lineRows[k] = rowNum;
        const sel = container.querySelector(`.sel-hdr-line-row[data-key="${k}"]`);
        if (sel) sel.value = rowNum.toString();
      });
      hdrConfig.line_rows = lineRows;

      notifyChange();
    });

    // 2. Drag and Drop для среднего блока (Middle, slot_1)
    const cardMiddle = document.getElementById("card_middle");
    setupBlockDragAndDrop(cardMiddle, ".tpl-middle-line-row", (newOrder, container) => {
      const targetTpl = tplKey || layoutState.currentTemplate || "cover";
      const s1 = ensureMiddleSlotDefaults(targetTpl);
      s1.item_order = newOrder;

      const checkedKeys = new Set(
        Array.from(container.querySelectorAll(".chk-slot-line:checked")).map((c) => c.dataset.key)
      );
      s1.lines = newOrder.filter((k) => checkedKeys.has(k));

      notifyChange();
    });

    // 3. Drag and Drop для подвала (Footer)
    const cardFooter = document.getElementById("card_footer");
    setupBlockDragAndDrop(cardFooter, ".tpl-ftr-line-row", (newOrder, container) => {
      const targetTpl = tplKey || layoutState.currentTemplate || "cover";
      if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
      if (!state.pdf_settings.custom_layouts[targetTpl]) state.pdf_settings.custom_layouts[targetTpl] = {};
      if (!state.pdf_settings.custom_layouts[targetTpl].footer) state.pdf_settings.custom_layouts[targetTpl].footer = {};
      const ftrConfig = state.pdf_settings.custom_layouts[targetTpl].footer;
      ftrConfig.item_order = newOrder;

      const checkedKeys = new Set(
        Array.from(container.querySelectorAll(".chk-ftr-line:checked")).map((c) => c.dataset.key)
      );
      ftrConfig.lines = newOrder.filter((k) => checkedKeys.has(k));

      notifyChange();
    });
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
        state.pdf_settings.margin = Math.round(((val * 72.0) / 25.4) * 10) / 10;
        if (window.bridge && typeof bridge.saveSettings === "function") {
          bridge.saveSettings(JSON.stringify(state.pdf_settings));
        }
        notifyChange();
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
          const defLines = defSlot.lines ? deepClone(defSlot.lines) : (DEFAULT_LINES_BY_CONTENT[slotDef.id] ? deepClone(DEFAULT_LINES_BY_CONTENT[slotDef.id]) : (defContent ? deepClone(DEFAULT_LINES_BY_CONTENT[defContent]) : []));
          const defLineRows = defSlot.line_rows ? deepClone(defSlot.line_rows) : (slotDef.default_line_rows ? deepClone(slotDef.default_line_rows) : null);
          const defLineFontSizes = defSlot.line_font_sizes ? deepClone(defSlot.line_font_sizes) : (slotDef.default_line_font_sizes ? deepClone(slotDef.default_line_font_sizes) : null);
          const defLineColors = defSlot.line_colors ? deepClone(defSlot.line_colors) : (slotDef.default_line_colors ? deepClone(slotDef.default_line_colors) : null);
          const defLineAligns = defSlot.line_aligns ? deepClone(defSlot.line_aligns) : (slotDef.default_line_aligns ? deepClone(slotDef.default_line_aligns) : null);
          state.pdf_settings.custom_layouts[tplKey][slotDef.id] = {
            visible: defSlot.visible !== false,
            content: defContent,
            custom_text: defSlot.custom_text || "",
            align: defSlot.align || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "left"),
            valign: defSlot.valign || (slotDef.id === "header" || slotDef.id === "footer" ? "center" : "top"),
            font_size: defFontSize,
            aspect_ratio: defSlot.aspect_ratio || "4:3",
            scale_pct: defSlot.scale_pct !== undefined ? defSlot.scale_pct : 100,
            lines: defLines,
            line_rows: defLineRows,
            line_font_sizes: defLineFontSizes,
            line_colors: defLineColors,
            line_aligns: defLineAligns,
            item_gap_mm: defSlot.item_gap_mm !== undefined ? defSlot.item_gap_mm : (defSlot.item_gap !== undefined ? defSlot.item_gap : (slotDef.id === "slot_1" ? 2 : undefined)),
            item_gap: defSlot.item_gap !== undefined ? defSlot.item_gap : (defSlot.item_gap_mm !== undefined ? defSlot.item_gap_mm : (slotDef.id === "slot_1" ? 2 : undefined)),
            opacity: defSlot.opacity !== undefined ? defSlot.opacity : 0.9,
            x: defSlot.x !== undefined ? defSlot.x : slotDef.x,
            y: defSlot.y !== undefined ? defSlot.y : slotDef.y,
            w: defSlot.w !== undefined ? defSlot.w : slotDef.w,
            h: defSlot.h !== undefined ? defSlot.h : slotDef.h
          };
        });

        renderTemplateSettingsList();
        showNotification(`Настройки шаблона «${defTpl.name}» сброшены к стандартам`, "success");
        notifyChange();
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
    if (els.inputFurnitureName) {
      const pTags = prj.product_tags || info.product_tags;
      els.inputFurnitureName.value = (Array.isArray(pTags) && pTags.length)
        ? pTags.join(", ")
        : (prj.product || info.name_product || info.furniture_name || "");
    }
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
    if (els.selectImageAspect) els.selectImageAspect.value = settings.image_aspect_ratio || "page";
    if (els.inputAspectCustomW) els.inputAspectCustomW.value = settings.custom_ratio_w || 16;
    if (els.inputAspectCustomH) els.inputAspectCustomH.value = settings.custom_ratio_h || 9;
    if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = settings.show_aspect_overlay === true;
    updateAspectUI();
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

    const obColor = settings.overlay_border_color ? (settings.overlay_border_color.startsWith("#") ? settings.overlay_border_color : `#${settings.overlay_border_color}`) : "#0EA5E9";
    if (els.inputOverlayBorderColor) els.inputOverlayBorderColor.value = obColor;
    if (els.overlayBorderColorHex) els.overlayBorderColorHex.textContent = obColor;

    const omColor = settings.overlay_mask_color ? (settings.overlay_mask_color.startsWith("#") ? settings.overlay_mask_color : `#${settings.overlay_mask_color}`) : "#0F172A";
    if (els.inputOverlayMaskColor) els.inputOverlayMaskColor.value = omColor;
    if (els.overlayMaskColorHex) els.overlayMaskColorHex.textContent = omColor;

    if (els.chkAutoOpen) els.chkAutoOpen.checked = settings.auto_open_pdf !== false;
    if (els.chkSaveBackup) els.chkSaveBackup.checked = settings.save_skp_backup !== false;
    if (els.chkAntialias) els.chkAntialias.checked = settings.antialias !== false;

    updateHeaderTitles();
    renderScenesTable();
    renderStadia();
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
      titleInput.addEventListener("change", (e) => {
        d.title = e.target.value.trim();
        notifyChange();
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
        notifyChange();
      });

      const btnDelete = document.createElement("button");
      btnDelete.type = "button";
      btnDelete.className = "btn-icon btn-delete";
      btnDelete.textContent = "✕";
      btnDelete.title = "Удалить этот раздел папки";
      btnDelete.addEventListener("click", () => {
        state.directories.splice(index, 1);
        renderDirectories();
        notifyChange();
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
        notifyChange();
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
        notifyChange();
      });
      descTextarea.addEventListener("change", (e) => {
        d.description = e.target.value;
        notifyChange();
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

  // Render API Targets (api_targets from project_config.yaml / settings)
  function renderApiTargets() {
    if (!els.apiTargetsList) return;
    els.apiTargetsList.innerHTML = "";
    if (!Array.isArray(state.api_targets)) {
      state.api_targets = [];
    }
    const targets = state.api_targets;
    if (targets.length === 0) {
      els.apiTargetsList.innerHTML = `
        <div class="empty-targets-placeholder">
          Адресаты API не заданы. Нажмите «+ Добавить URL», чтобы добавить адрес веб-интеграции.
        </div>`;
      return;
    }
    targets.forEach((targetUrl, index) => {
      const card = document.createElement("div");
      card.className = "api-target-card";
      card.dataset.index = index;

      const icon = document.createElement("span");
      icon.className = "api-target-icon";
      icon.textContent = "🌐";

      const badge = document.createElement("span");
      badge.className = "api-target-badge";
      badge.textContent = `#${index + 1}`;

      const input = document.createElement("input");
      input.type = "text";
      input.className = "form-control api-target-input";
      input.value = targetUrl || "";
      input.placeholder = "https://domain.com/api/projects?token=...";
      input.title = "URL адресата веб-интеграции";
      input.addEventListener("input", (e) => {
        state.api_targets[index] = e.target.value;
      });
      input.addEventListener("change", (e) => {
        state.api_targets[index] = e.target.value.trim();
        notifyChange();
      });

      const btnDelete = document.createElement("button");
      btnDelete.type = "button";
      btnDelete.className = "btn-icon btn-delete";
      btnDelete.textContent = "✕";
      btnDelete.title = "Удалить этот адрес API";
      btnDelete.addEventListener("click", () => {
        state.api_targets.splice(index, 1);
        renderApiTargets();
        notifyChange();
      });

      card.appendChild(icon);
      card.appendChild(badge);
      card.appendChild(input);
      card.appendChild(btnDelete);

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
    notifyChange();
  }

  // Update Aspect Ratio UI & SketchUp Overlay state
  function updateAspectUI() {
    const aspectMode = els.selectImageAspect ? els.selectImageAspect.value : "page";
    if (els.customAspectGroup) {
      els.customAspectGroup.style.display = (aspectMode === "custom") ? "block" : "none";
    }

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A4").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const qualityScale = parseFloat(els.selectQuality ? els.selectQuality.value : 2.0) || 2.0;
    const baseWidth = Math.round(1200 * qualityScale);

    let ratio = 1.4142;
    let label = "A4 Альбомный";

    if (aspectMode === "16:9") {
      ratio = 16.0 / 9.0;
      label = "16:9 (Широкий экран)";
    } else if (aspectMode === "4:3") {
      ratio = 4.0 / 3.0;
      label = "4:3 (Традиционный)";
    } else if (aspectMode === "3:2") {
      ratio = 3.0 / 2.0;
      label = "3:2 (Фотокадр)";
    } else if (aspectMode === "1:1") {
      ratio = 1.0;
      label = "1:1 (Квадрат)";
    } else if (aspectMode === "custom") {
      const cw = parseFloat(els.inputAspectCustomW ? els.inputAspectCustomW.value : 16) || 16;
      const ch = parseFloat(els.inputAspectCustomH ? els.inputAspectCustomH.value : 9) || 9;
      ratio = cw / Math.max(0.01, ch);
      label = `Кастомный (${cw.toFixed(1)}:${ch.toFixed(1)})`;
    } else {
      // page
      let dim = [297, 210];
      if (pageSize === "A3") dim = [420, 297];
      else if (pageSize === "A2") dim = [594, 420];
      else if (pageSize === "LETTER") dim = [279.4, 215.9];

      if (pageLayout === "portrait") {
        ratio = dim[1] / dim[0];
        label = `${pageSize} Книжный (${ratio.toFixed(2)}:1)`;
      } else {
        ratio = dim[0] / dim[1];
        label = `${pageSize} Альбомный (${ratio.toFixed(2)}:1)`;
      }
    }

    const renderH = Math.round(baseWidth / ratio);
    if (els.aspectOverlayBadge) {
      els.aspectOverlayBadge.textContent = `${label} • ${baseWidth} × ${renderH} px`;
    }

    // Отправка обновленных настроек в SketchUp для оверлея
    if (window.sketchup && typeof window.sketchup.updateAspectSettings === "function") {
      const payload = {
        image_aspect_ratio: aspectMode,
        custom_ratio_w: parseFloat(els.inputAspectCustomW ? els.inputAspectCustomW.value : 16) || 16,
        custom_ratio_h: parseFloat(els.inputAspectCustomH ? els.inputAspectCustomH.value : 9) || 9,
        page_size: pageSize,
        page_layout: pageLayout,
        image_width: baseWidth
      };
      callRuby("updateAspectSettings", JSON.stringify(payload));
    }
    notifyChange();
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
    notifyChange();
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

      // Checkbox & Number (two rows in one cell)
      const tdNumCheck = document.createElement("td");
      tdNumCheck.className = "scene-num-check-cell";

      const numCheckWrap = document.createElement("div");
      numCheckWrap.className = "scene-num-check-wrap";

      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = scene.enabled !== false;
      chk.title = "Включить / исключить сцену из экспорта в PDF";
      chk.addEventListener("change", (e) => {
        scene.enabled = e.target.checked;
        updateSceneBadge();
        renderLayoutCanvas();
        updateLayoutUsageBadge();
        notifyChange();
      });
      chk.addEventListener("click", (e) => e.stopPropagation());

      const numRow = document.createElement("div");
      numRow.className = "scene-num-row";
      numRow.title = "Перетащите строку мышью для изменения порядка";
      const dragHandle = document.createElement("span");
      dragHandle.className = "drag-handle";
      dragHandle.textContent = "⠿";
      const rowNum = document.createElement("span");
      rowNum.className = "row-num";
      rowNum.textContent = index + 1;
      numRow.appendChild(dragHandle);
      numRow.appendChild(rowNum);

      numCheckWrap.appendChild(chk);
      numCheckWrap.appendChild(numRow);
      tdNumCheck.appendChild(numCheckWrap);

      // Scene Name & Description (two rows in one cell)
      const tdInfo = document.createElement("td");
      tdInfo.className = "scene-info-cell";

      const infoWrap = document.createElement("div");
      infoWrap.className = "scene-info-wrap";

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
        notifyChange();
      });
      inputName.addEventListener("keydown", (e) => {
        if (e.key === "Enter") inputName.blur();
      });
      inputName.addEventListener("click", (e) => e.stopPropagation());

      const inputDesc = document.createElement("input");
      inputDesc.type = "text";
      inputDesc.className = "table-input scene-desc-input";
      inputDesc.value = scene.description || "";
      inputDesc.placeholder = "Описание на листе...";
      inputDesc.title = "Описание / примечание на листе";
      inputDesc.addEventListener("input", (e) => {
        scene.description = e.target.value;
        renderLayoutCanvas();
      });
      inputDesc.addEventListener("change", (e) => {
        scene.description = e.target.value.trim();
        e.target.value = scene.description;
        renderTemplateSettingsList();
        notifyChange();
      });
      inputDesc.addEventListener("keydown", (e) => {
        if (e.key === "Enter") inputDesc.blur();
      });
      inputDesc.addEventListener("click", (e) => e.stopPropagation());

      infoWrap.appendChild(inputName);
      infoWrap.appendChild(inputDesc);
      tdInfo.appendChild(infoWrap);

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
        notifyChange();
      });
      selType.addEventListener("click", (e) => e.stopPropagation());
      tdType.appendChild(selType);

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
          notifyChange();
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

      tr.appendChild(tdNumCheck);
      tr.appendChild(tdInfo);
      tr.appendChild(tdType);

      els.scenesTableBody.appendChild(tr);
    });

    updateLayoutUsageBadge();
  }

  // Render Stadia Checkboxes
  function renderStadia() {
    if (!els.stadiaCheckboxesContainer) return;
    els.stadiaCheckboxesContainer.innerHTML = "";

    const defaultStadia = [
      { name: "Предварительный проект", status: true },
      { name: "Правки проекта (история правок)", status: true },
      { name: "Выбраны материалы и фурнитура", status: true },
      { name: "Предварительно Утвержден", status: false },
      { name: "Проверка технологом", status: false },
      { name: "Утвержден", status: false },
      { name: "Отправлен в производство", status: false },
      { name: "Оплачен", status: false }
    ];

    let stadia = state.workflow?.stadia;
    if (!Array.isArray(stadia) || stadia.length === 0) {
      stadia = defaultStadia;
      state.workflow = state.workflow || {};
      state.workflow.stadia = stadia;
    }

    stadia.forEach((st, idx) => {
      const label = document.createElement("label");
      label.className = `stadia-checkbox-item ${st.status ? "checked" : ""}`;

      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = !!st.status;

      chk.addEventListener("change", (e) => {
        st.status = e.target.checked;
        label.classList.toggle("checked", st.status);

        // Обновляем текущий статус в выпадающем списке/поле
        const lastChecked = [...stadia].reverse().find(s => s.status);
        if (lastChecked && els.inputStatus) {
          const opts = Array.from(els.inputStatus.options).map(o => o.value);
          if (opts.includes(lastChecked.name)) {
            els.inputStatus.value = lastChecked.name;
          }
        }
      });

      const span = document.createElement("span");
      span.textContent = st.name || `Стадия ${idx + 1}`;

      label.appendChild(chk);
      label.appendChild(span);
      els.stadiaCheckboxesContainer.appendChild(label);
    });
  }

  // Render History Table
  function renderHistoryTable() {
    els.historyTableBody.innerHTML = "";
    const history = state.history || [];

    history.forEach((item, index) => {
      const tr = document.createElement("tr");

      // 1. Дата и время (data / date)
      const tdDate = document.createElement("td");
      const inputDate = document.createElement("input");
      inputDate.type = "text";
      inputDate.className = "table-input font-mono";
      inputDate.value = item.data || item.date || "";
      inputDate.placeholder = "ГГГГ-ММ-ДД ЧЧ:ММ";
      inputDate.addEventListener("input", (e) => {
        item.data = e.target.value;
        item.date = e.target.value;
      });
      inputDate.addEventListener("change", (e) => {
        item.data = e.target.value;
        item.date = e.target.value;
        notifyChange();
      });
      tdDate.appendChild(inputDate);

      // 2. Комментарий к правке (edit / text)
      const tdDesc = document.createElement("td");
      const inputDesc = document.createElement("input");
      inputDesc.type = "text";
      inputDesc.className = "table-input";
      inputDesc.value = item.edit || item.text || item.description || "";
      inputDesc.placeholder = "Текст правки / комментарий...";
      inputDesc.addEventListener("input", (e) => {
        item.edit = e.target.value;
        item.text = e.target.value;
        item.description = e.target.value;
        // Синхронизируем верхнюю (самую свежую) запись с полем last_edit
        if (index === 0 && els.inputLastEdit) {
          els.inputLastEdit.value = e.target.value;
        }
      });
      inputDesc.addEventListener("change", (e) => {
        item.edit = e.target.value;
        item.text = e.target.value;
        item.description = e.target.value;
        if (index === 0 && els.inputLastEdit) {
          els.inputLastEdit.value = e.target.value;
        }
        notifyChange();
      });
      tdDesc.appendChild(inputDesc);

      // 3. Файл PDF (pdf_link)
      const tdPdfLink = document.createElement("td");
      const inputPdfLink = document.createElement("input");
      inputPdfLink.type = "text";
      inputPdfLink.className = "table-input font-mono";
      inputPdfLink.value = item.pdf_link || "";
      inputPdfLink.placeholder = "HF#..._version_revision.pdf";
      inputPdfLink.addEventListener("input", (e) => {
        item.pdf_link = e.target.value;
      });
      inputPdfLink.addEventListener("change", (e) => {
        item.pdf_link = e.target.value;
        notifyChange();
      });
      tdPdfLink.appendChild(inputPdfLink);

      // 4. Удаление
      const tdDelete = document.createElement("td");
      const btnDel = document.createElement("button");
      btnDel.className = "btn-icon btn-delete";
      btnDel.textContent = "✕";
      btnDel.title = "Удалить запись";
      btnDel.addEventListener("click", () => {
        state.history.splice(index, 1);
        renderHistoryTable();
        notifyChange();
      });
      tdDelete.appendChild(btnDel);

      tr.appendChild(tdDate);
      tr.appendChild(tdDesc);
      tr.appendChild(tdPdfLink);
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
    const productTags = furniture
      ? furniture.split(",").map((s) => s.trim()).filter(Boolean)
      : (state.project?.product_tags || []);

    state.project = {
      articul: articulVal,
      product_tags: productTags,
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
      stadia: state.workflow?.stadia || [],
      history_edit: historyEditPairs
    };

    // Модуль 4: Корневой history_edit (project.yaml)
    state.history_edit = (state.history || []).map((item) => ({
      data: item.data || item.date || "",
      edit: item.edit || item.text || item.description || "",
      pdf_link: item.pdf_link || ""
    }));

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
      image_aspect_ratio: els.selectImageAspect ? els.selectImageAspect.value : (state.pdf_settings?.image_aspect_ratio || "page"),
      custom_ratio_w: els.inputAspectCustomW ? parseFloat(els.inputAspectCustomW.value) || 16 : 16,
      custom_ratio_h: els.inputAspectCustomH ? parseFloat(els.inputAspectCustomH.value) || 9 : 9,
      show_aspect_overlay: (function() {
        const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
        if (chkTpl) return chkTpl.checked;
        return Boolean(state.pdf_settings && state.pdf_settings.show_aspect_overlay);
      })(),
      overlay_border_color: (function() {
        const inpTpl = document.getElementById("input_overlay_border_color");
        if (inpTpl && inpTpl.value) return inpTpl.value;
        if (els.inputOverlayBorderColor && els.inputOverlayBorderColor.value) return els.inputOverlayBorderColor.value;
        return state.pdf_settings?.overlay_border_color || "#0EA5E9";
      })(),
      overlay_border_opacity: (function() {
        const inpTpl = document.getElementById("input_overlay_border_opacity");
        if (inpTpl && inpTpl.value !== "") return parseInt(inpTpl.value, 10) || 100;
        return state.pdf_settings?.overlay_border_opacity !== undefined ? parseInt(state.pdf_settings.overlay_border_opacity, 10) : 100;
      })(),
      overlay_mask_color: (function() {
        const inpTpl = document.getElementById("input_overlay_mask_color");
        if (inpTpl && inpTpl.value) return inpTpl.value;
        if (els.inputOverlayMaskColor && els.inputOverlayMaskColor.value) return els.inputOverlayMaskColor.value;
        return state.pdf_settings?.overlay_mask_color || "#0F172A";
      })(),
      overlay_mask_opacity: (function() {
        const inpTpl = document.getElementById("input_overlay_mask_opacity");
        if (inpTpl && inpTpl.value !== "") return parseInt(inpTpl.value, 10) || 55;
        return state.pdf_settings?.overlay_mask_opacity !== undefined ? parseInt(state.pdf_settings.overlay_mask_opacity, 10) : 55;
      })(),
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

    // Синхронизация адресатов API из элементов ввода интерфейса
    if (els.apiTargetsList) {
      const inputs = els.apiTargetsList.querySelectorAll(".api-target-input");
      state.api_targets = Array.from(inputs).map((inp) => inp.value.trim()).filter(Boolean);
    } else if (Array.isArray(state.api_targets)) {
      state.api_targets = state.api_targets.map((t) => String(t).trim()).filter(Boolean);
    }

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
        notifyChange();
      });
    }

    // API Targets Add button
    if (els.btnAddApiTarget) {
      els.btnAddApiTarget.addEventListener("click", () => {
        if (!Array.isArray(state.api_targets)) state.api_targets = [];
        state.api_targets.push("");
        renderApiTargets();
        notifyChange();
        if (els.apiTargetsList) {
          const inputs = els.apiTargetsList.querySelectorAll(".api-target-input");
          if (inputs.length > 0) {
            inputs[inputs.length - 1].focus();
          }
        }
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

    // Page orientation / size change updates layout canvas sheet and aspect overlay
    if (els.selectPageLayout) {
      els.selectPageLayout.addEventListener("change", () => {
        renderLayoutCanvas();
        updateAspectUI();
      });
    }
    if (els.selectPageSize) {
      els.selectPageSize.addEventListener("change", () => {
        renderLayoutCanvas();
        updateAspectUI();
      });
    }

    if (els.selectImageAspect) {
      els.selectImageAspect.addEventListener("change", updateAspectUI);
    }
    if (els.inputAspectCustomW) {
      els.inputAspectCustomW.addEventListener("input", updateAspectUI);
    }
    if (els.inputAspectCustomH) {
      els.inputAspectCustomH.addEventListener("input", updateAspectUI);
    }
    if (els.selectQuality) {
      els.selectQuality.addEventListener("change", updateAspectUI);
    }
    if (els.chkShowAspectOverlay) {
      els.chkShowAspectOverlay.addEventListener("change", (e) => {
        if (window.sketchup && typeof window.sketchup.toggleAspectOverlay === "function") {
          callRuby("toggleAspectOverlay", e.target.checked);
        }
      });
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

    if (els.inputOverlayBorderColor) {
      const handleOverlayBorderColor = (e) => {
        const val = e.target.value.toUpperCase();
        if (els.overlayBorderColorHex) els.overlayBorderColorHex.textContent = val;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_border_color = val;
        const inpTpl = document.getElementById("input_overlay_border_color");
        if (inpTpl) inpTpl.value = val;
        const lblTpl = document.getElementById("val_overlay_border_color");
        if (lblTpl) lblTpl.textContent = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      els.inputOverlayBorderColor.addEventListener("input", handleOverlayBorderColor);
      els.inputOverlayBorderColor.addEventListener("change", handleOverlayBorderColor);
    }

    if (els.inputOverlayMaskColor) {
      const handleOverlayMaskColor = (e) => {
        const val = e.target.value.toUpperCase();
        if (els.overlayMaskColorHex) els.overlayMaskColorHex.textContent = val;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_mask_color = val;
        const inpTpl = document.getElementById("input_overlay_mask_color");
        if (inpTpl) inpTpl.value = val;
        const lblTpl = document.getElementById("val_overlay_mask_color");
        if (lblTpl) lblTpl.textContent = val;
        syncCurrentTemplateOverlay();
        notifyChange();
      };
      els.inputOverlayMaskColor.addEventListener("input", handleOverlayMaskColor);
      els.inputOverlayMaskColor.addEventListener("change", handleOverlayMaskColor);
    }

    // Quick Scene Selection
    els.btnSelectAllScenes.addEventListener("click", () => {
      state.scenes.forEach((s) => (s.enabled = true));
      renderScenesTable();
      notifyChange();
    });

    els.btnDeselectAllScenes.addEventListener("click", () => {
      state.scenes.forEach((s) => (s.enabled = false));
      renderScenesTable();
      notifyChange();
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
      notifyChange();
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
        data: nowStr,
        date: nowStr,
        edit: defaultText,
        text: defaultText,
        description: defaultText,
        pdf_link: ""
      });

      if (els.inputLastEdit) els.inputLastEdit.value = defaultText;
      renderHistoryTable();
      notifyChange();
    });

    // Actual export execution helper
    function executeExport() {
      const data = collectFormData();
      els.progressBarFill.style.width = "0%";
      els.progressPercent.textContent = "0%";
      els.progressMessage.textContent = "Инициализация...";
      els.progressOverlay.classList.remove("hidden");

      callRuby("startExport", JSON.stringify(data));
    }

    // Start Export: prompt user for revision notes before export
    els.btnStartExport.addEventListener("click", () => {
      const data = collectFormData();
      const enabledScenes = (data.scenes || []).filter((s) => s.enabled && s.page_type !== "skip");
      if (enabledScenes.length === 0) {
        showNotification("Выберите хотя бы одну сцену для экспорта!", "error");
        return;
      }

      // Точная дата и время перед созданием PDF
      const now = new Date();
      const y = now.getFullYear();
      const m = String(now.getMonth() + 1).padStart(2, '0');
      const d = String(now.getDate()).padStart(2, '0');
      const hh = String(now.getHours()).padStart(2, '0');
      const mm = String(now.getMinutes()).padStart(2, '0');
      const exactTimeStr = `${y}-${m}-${d} ${hh}:${mm}`;

      const currRevNum = parseInt(els.inputRevision ? els.inputRevision.value : 1, 10) || 1;
      const nextRevNum = currRevNum + 1;
      const currRevStr = `r${String(currRevNum).padStart(3, '0')}`;
      const nextRevStr = `r${String(nextRevNum).padStart(3, '0')}`;

      if (els.revPromptDateTime) {
        els.revPromptDateTime.textContent = exactTimeStr;
        els.revPromptDateTime.setAttribute("data-exact", exactTimeStr);
      }
      if (els.revPromptCurrentRev) els.revPromptCurrentRev.textContent = currRevStr;
      if (els.revPromptNextRev) els.revPromptNextRev.textContent = nextRevStr;
      if (els.inputRevisionNote) {
        els.inputRevisionNote.value = "";
      }

      if (els.revisionPromptModal) {
        els.revisionPromptModal.classList.remove("hidden");
        setTimeout(() => {
          if (els.inputRevisionNote) els.inputRevisionNote.focus();
        }, 50);
      } else {
        executeExport();
      }
    });

    // Revision Prompt Modal: Cancel
    if (els.btnCancelExportModal) {
      els.btnCancelExportModal.addEventListener("click", () => {
        if (els.revisionPromptModal) els.revisionPromptModal.classList.add("hidden");
      });
    }

    // Revision Prompt Modal: Export without recording edits
    if (els.btnSkipRevisionExport) {
      els.btnSkipRevisionExport.addEventListener("click", () => {
        if (els.revisionPromptModal) els.revisionPromptModal.classList.add("hidden");
        executeExport();
      });
    }

    // Revision Prompt Modal: Confirm Revision & Export
    if (els.btnConfirmRevisionExport) {
      els.btnConfirmRevisionExport.addEventListener("click", () => {
        const rawNote = (els.inputRevisionNote ? els.inputRevisionNote.value : "").trim();
        if (!rawNote) {
          showNotification("Введите описание правок или нажмите «Без записи правок»", "warning");
          if (els.inputRevisionNote) els.inputRevisionNote.focus();
          return;
        }

        const note = rawNote.replace(/\r?\n+/g, "; ");
        const exactTime = (els.revPromptDateTime && els.revPromptDateTime.getAttribute("data-exact")) || (() => {
          const now = new Date();
          const y = now.getFullYear();
          const m = String(now.getMonth() + 1).padStart(2, '0');
          const d = String(now.getDate()).padStart(2, '0');
          const hh = String(now.getHours()).padStart(2, '0');
          const mm = String(now.getMinutes()).padStart(2, '0');
          return `${y}-${m}-${d} ${hh}:${mm}`;
        })();

        const currRevNum = parseInt(els.inputRevision ? els.inputRevision.value : 1, 10) || 1;
        const nextRevNum = currRevNum + 1;
        const nextRevStr = String(nextRevNum).padStart(3, '0');
        const entryText = `${note} (rev. ${nextRevStr})`;

        // Добавляем новую запись в историю проекта
        state.history.unshift({
          date: exactTime,
          text: entryText,
          description: entryText
        });

        // Синхронизируем состояние и форму
        state.workflow.revision = nextRevStr;
        state.workflow.last_edit = note;
        if (els.inputRevision) els.inputRevision.value = nextRevStr;
        if (els.inputLastEdit) els.inputLastEdit.value = note;

        renderHistoryTable();

        if (els.revisionPromptModal) els.revisionPromptModal.classList.add("hidden");
        executeExport();
      });
    }

    if (els.inputRevisionNote) {
      els.inputRevisionNote.addEventListener("keydown", (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
          e.preventDefault();
          if (els.btnConfirmRevisionExport) els.btnConfirmRevisionExport.click();
        } else if (e.key === "Escape") {
          if (els.revisionPromptModal) els.revisionPromptModal.classList.add("hidden");
        }
      });
    }

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

    // Auto-save listeners for all dialog input fields across tabs
    const autoSaveInputIds = [
      "inputRoomName", "inputFurnitureName", "inputCustomer", "inputCustomerId",
      "inputCompany", "inputArticul", "selectTrade", "inputTags",
      "inputProjectDescription", "inputAddress", "inputPhone", "inputEmail",
      "inputAuthor", "inputPrice", "inputStartDate", "inputEndDate",
      "inputTotalDuration", "inputStatus", "inputRevision", "inputVersion",
      "inputLastEdit", "inputTaskDescription", "inputTaskDimensions", "inputTaskWishes",
      "inputMaterials", "inputAppliances", "inputLighting", "inputNotes",
      "selectExportEngine", "selectLayoutRenderMode", "chkSaveLayoutFile",
      "selectPageSize", "selectPageLayout", "inputPageMargin", "inputLayoutMargin",
      "selectImageAspect", "inputAspectCustomW", "inputAspectCustomH",
      "selectQuality", "selectStamp", "inputCustomStamp",
      "inputPrimaryColor", "inputStampColor", "chkAutoOpen", "chkSaveBackup", "chkAntialias"
    ];
    autoSaveInputIds.forEach((id) => {
      const el = (els && els[id]) || document.getElementById(id);
      if (el) {
        el.addEventListener("input", () => notifyChange());
        el.addEventListener("change", () => notifyChange());
      }
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

    onAutoSaved: function (yamlName) {
      const timeStr = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      const label = yamlName ? `Сохранено (${yamlName})` : `Сохранено ${timeStr}`;
      updateAutoSaveIndicator("saved", label);
    },

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

      // Update revision locally from backend if provided
      if (els.inputRevision && newRevision !== undefined && newRevision !== null) {
        els.inputRevision.value = newRevision;
      }
    },

    onExportError: function (errorMsg) {
      els.progressOverlay.classList.add("hidden");
      showNotification(`Ошибка экспорта: ${errorMsg}`, "error");
    },

    syncOverlayState: function (isActive) {
      if (!state.pdf_settings) state.pdf_settings = {};
      state.pdf_settings.show_aspect_overlay = Boolean(isActive);
      if (els.chkShowAspectOverlay) {
        els.chkShowAspectOverlay.checked = Boolean(isActive);
      }
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) {
        chkTpl.checked = Boolean(isActive);
      }
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) {
        tplBadge.classList.toggle("disabled-overlay", !isActive);
      }
    },

    updateAspectInfo: function (info) {
      if (els.aspectOverlayBadge && info) {
        els.aspectOverlayBadge.textContent = `${info.label} • ${info.render_w} × ${info.render_h} px`;
      }
      const tplText = document.getElementById("tplAspectOverlayText");
      if (tplText && info) {
        const displayLabel = info.label ? (info.label === "page" ? "ПО ЛИСТУ" : info.label.toUpperCase()) : "";
        tplText.textContent = `📐 РАМКА: ${displayLabel}`;
      }
      const tplNote = document.querySelector(".tpl-image-note");
      if (tplNote && info) {
        const displayLabel = info.label ? (info.label === "page" ? "по листу" : info.label) : "";
        tplNote.textContent = `Рамка в окне SketchUp отображает точные границы кадра для текущего шаблона с выбранными пропорциями (${displayLabel}).`;
      }
    },

    setAspectRatio: function (ratio) {
      const grpRatio = document.getElementById("grp_image_aspect_ratio");
      if (grpRatio) {
        grpRatio.querySelectorAll(".btn-aspect-ratio").forEach((b) => {
          b.classList.toggle("active", b.dataset.ratio === ratio);
        });
      }
      updateBlockSlot("image_4_3", { aspect_ratio: ratio });
      if (!state.pdf_settings) state.pdf_settings = {};
      state.pdf_settings.show_aspect_overlay = true;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = true;
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) chkTpl.checked = true;
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) tplBadge.classList.remove("disabled-overlay");
      callRuby("toggleAspectOverlay", true);
      syncCurrentTemplateOverlay(ratio);
      notifyChange();
    },

    onAutoSaved: function (yamlName) {
      updateAutoSaveIndicator("saved", yamlName ? `Сохранено (${yamlName})` : "Сохранено");
    },

    syncCurrentTemplateOverlay: syncCurrentTemplateOverlay
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
