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
    { key: "articul",          group: "project",  label: "Артикул",                 icon: "🔖", getVal: (info, wf) => (info.articul || "").trim() || "CF#260905_160129" },
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
        const art = (info.articul || '').trim() || 'CF#260905_160129';
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
        const art = (info.articul || '').trim() || 'CF#260905_160129';
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

  // Helper to resolve info line definitions including dynamic directory lines
  function getInfoLineDef(key) {
    if (!key) return null;
    const found = AVAILABLE_INFO_LINES.find((l) => l.key === key);
    if (found) return found;

    if (typeof key === "string" && key.startsWith("dir_desc_")) {
      const idx = parseInt(key.replace("dir_desc_", ""), 10);
      const dirs = Array.isArray(state.directories) ? state.directories : [];
      const d = dirs[idx] || {};
      const dTitle = (d.title || getFolderName(d.path) || `Раздел #${idx + 1}`).trim();
      return {
        key: key,
        group: "specs",
        label: `📁 ${dTitle}`,
        icon: "📁",
        getVal: () => (d.description || "").trim() || "—"
      };
    }

    if (key === "dir_specs" || key === "directories_spec") {
      return {
        key: key,
        group: "specs",
        label: "📁 Все спецификации папок",
        icon: "📁",
        getVal: () => {
          const dirs = (state.directories || []).filter(d => d && (d.description || "").trim());
          if (dirs.length === 0) return "—";
          return dirs.map((d, i) => `${d.title || ("Раздел #" + (i + 1))}: ${(d.description || "").trim()}`).join(" • ");
        }
      };
    }

    return null;
  }

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
    show_titles: true,
    line_show_titles: {},
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
    },
    blank: {
      name: "Без шаблона (Blank)",
      slots: {
        header: { visible: false, content: "none", valign: "top", font_size: 11, lines: [], opacity: 0 },
        image_4_3: { visible: true, content: "render_viewport", aspect_ratio: "16:9", scale_pct: 100 },
        slot_1: { visible: false, content: "none", align: "left", valign: "top", font_size: 8, lines: [], opacity: 0 },
        slot_2: { visible: false, content: "none", align: "left", valign: "bottom", font_size: 8, lines: [], opacity: 0 },
        slot_3: { visible: false, content: "none", align: "right", valign: "top", font_size: 8, lines: [], opacity: 0 },
        slot_4: { visible: false, content: "none", align: "right", valign: "bottom", font_size: 8, lines: [], opacity: 0 },
        footer: { visible: false, content: "none", align: "center", valign: "bottom", font_size: 8.5, lines: [], opacity: 0 }
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

    // Tab 1 Inputs (Modular Project, Customer, Workflow)
    inputRoomName: document.getElementById("inputRoomName"),
    inputFurnitureName: document.getElementById("inputFurnitureName"),
    inputCustomer: document.getElementById("inputCustomer"),
    inputCustomerId: document.getElementById("inputCustomerId"),
    btnGenerateCustomerId: document.getElementById("btnGenerateCustomerId"),
    inputCompany: document.getElementById("inputCompany"),
    companyFieldGroup: document.getElementById("companyFieldGroup"),
    inputArticul: document.getElementById("inputArticul"),
    headerTradeBadge: document.getElementById("headerTradeBadge"),
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
    chkScenesBackground: document.getElementById("chk_scenes_background"),
    scenesPanel: document.getElementById("scenesPanel"),
    scenesSplitResizer: document.getElementById("scenesSplitResizer"),

    // Template & List Settings Elements
    templatesSidebar: document.getElementById("templatesSidebar"),
    templatesList: document.getElementById("templatesList"),
    btnCreateTemplate: document.getElementById("btnCreateTemplate"),
    btnDeleteTemplateSidebar: document.getElementById("btnDeleteTemplateSidebar"),
    currentTemplateTitle: document.getElementById("currentTemplateTitle"),
    btnRenameCurrentTemplate: document.getElementById("btnRenameCurrentTemplate"),
    btnDeleteCurrentTemplate: document.getElementById("btnDeleteCurrentTemplate"),
    newTemplateModal: document.getElementById("newTemplateModal"),
    inputNewTemplateName: document.getElementById("inputNewTemplateName"),
    selectNewTemplateBase: document.getElementById("selectNewTemplateBase"),
    btnConfirmNewTemplate: document.getElementById("btnConfirmNewTemplate"),
    btnCancelNewTemplate: document.getElementById("btnCancelNewTemplate"),
    deleteTemplateModal: document.getElementById("deleteTemplateModal"),
    deleteTemplateMsg: document.getElementById("deleteTemplateMsg"),
    btnCancelDeleteTemplate: document.getElementById("btnCancelDeleteTemplate"),
    btnConfirmDeleteTemplate: document.getElementById("btnConfirmDeleteTemplate"),
    renameTemplateModal: document.getElementById("renameTemplateModal"),
    inputRenameTemplateName: document.getElementById("inputRenameTemplateName"),
    btnCancelRenameTemplate: document.getElementById("btnCancelRenameTemplate"),
    btnConfirmRenameTemplate: document.getElementById("btnConfirmRenameTemplate"),
    templateSettingsPanel: document.getElementById("templateSettingsPanel"),
    templateSettingsContainer: document.getElementById("templateSettingsContainer"),
    selectLayoutTemplate: document.getElementById("selectLayoutTemplate"),
    layoutPageInfoBadge: document.getElementById("layoutPageInfoBadge"),
    inputLayoutMargin: document.getElementById("inputLayoutMargin"),
    btnResetLayout: document.getElementById("btnResetLayout"),

    // Tab 3 Inputs
    layoutRenderModeGroup: document.getElementById("layoutRenderModeGroup"),
    selectLayoutRenderMode: document.getElementById("selectLayoutRenderMode"),
    compressionGroup: document.getElementById("compressionGroup"),
    selectCompression: document.getElementById("selectCompression"),
    imageFormatGroup: document.getElementById("imageFormatGroup"),
    selectImageFormat: document.getElementById("selectImageFormat"),
    webpQualityGroup: document.getElementById("webpQualityGroup"),
    hintWebpFormat: document.getElementById("hintWebpFormat"),
    selectWebpQuality: document.getElementById("selectWebpQuality"),
    layoutSaveFileGroup: document.getElementById("layoutSaveFileGroup"),
    chkSaveLayoutFile: document.getElementById("chkSaveLayoutFile"),
    selectPageSize: document.getElementById("selectPageSize"),
    selectPageLayout: document.getElementById("selectPageLayout"),
    inputPageMargin: document.getElementById("inputPageMargin"),
    selectFontFamily: document.getElementById("selectFontFamily"),
    selectLayoutFontFamily: document.getElementById("selectLayoutFontFamily"),
    selectFontWeight: document.getElementById("selectFontWeight"),
    selectFontWidth: document.getElementById("selectFontWidth"),
    selectImageAspect: document.getElementById("selectImageAspect"),
    customAspectGroup: document.getElementById("customAspectGroup"),
    inputAspectCustomW: document.getElementById("inputAspectCustomW"),
    inputAspectCustomH: document.getElementById("inputAspectCustomH"),
    chkShowAspectOverlay: document.getElementById("chkShowAspectOverlay"),
    aspectOverlayBadge: document.getElementById("aspectOverlayBadge"),
    selectQuality: document.getElementById("selectQuality"),
    selectScaleMultiplier: document.getElementById("selectScaleMultiplier"),
    selectAnnotationFontSize: document.getElementById("selectAnnotationFontSize"),
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
    btnSaveYaml: document.getElementById("btnSaveYaml"),
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
    btnCancelExportModal: document.getElementById("btnCancelExportModal"),

    // Articul Prompt Modal (сохранение/экспорт без артикула)
    articulPromptModal: document.getElementById("articulPromptModal"),
    inputArticulPrompt: document.getElementById("inputArticulPrompt"),
    btnConfirmArticulSave: document.getElementById("btnConfirmArticulSave"),
    btnCancelArticulPrompt: document.getElementById("btnCancelArticulPrompt"),

    // Articul Type Modal (предложение создать артикул при открытии панели)
    articulTypeModal: document.getElementById("articulTypeModal"),
    btnArticulTypeCommercial: document.getElementById("btnArticulTypeCommercial"),
    btnArticulTypeHousehold: document.getElementById("btnArticulTypeHousehold"),
    btnArticulTypeLater: document.getElementById("btnArticulTypeLater")
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

  // Эффективное семейство для предпросмотра: параметр ширины повышает
  // сжатие Sofia Sans Condensed до Extra Condensed (зеркало FontService.apply_font_width)
  function previewFontFamilyFor(family, width) {
    const f = (family || "").toLowerCase();
    if (!f.includes("sofia sans condensed")) return family || "Sofia Sans Condensed";
    return width === "extra_condensed" ? "Sofia Sans Extra Condensed" : "Sofia Sans Condensed";
  }

  function getEffectiveRenderWidth() {
    if (els.selectQuality) {
      const val = (els.selectQuality.value || "").toLowerCase().trim();
      const pageSz = (els.selectPageSize ? els.selectPageSize.value : (state.pdf_settings?.page_size || "A3")).toUpperCase().trim();
      const pageLay = (els.selectPageLayout ? els.selectPageLayout.value : (state.pdf_settings?.page_layout || "landscape")).toLowerCase().trim();

      let dpi = 150;
      if (val === "low") dpi = 96;
      else if (val === "high") dpi = 300;
      else if (val === "medium") dpi = 150;
      else if (parseFloat(val) > 100) return Math.round(parseFloat(val));

      // Разрешение всегда рассчитывается по длинной стороне листа:
      // A4 (297 мм = 11.6929 дюйма): 96 dpi = 1123 px, 150 dpi = 1754 px, 300 dpi = 3508 px
      // A3 (420 мм = 16.5354 дюйма): 96 dpi = 1587 px, 150 dpi = 2480 px, 300 dpi = 4961 px
      const longInches = (pageSz === "A3") ? 16.535433 : 11.692913;
      return Math.round(longInches * dpi);
    }
    return state.pdf_settings?.image_width ? (parseInt(state.pdf_settings.image_width, 10) || 2400) : 2400;
  }

  function getEffectiveScaleMultiplier() {
    if (els.selectScaleMultiplier) {
      const raw = els.selectScaleMultiplier.value;
      if (raw === "auto") {
        const renderMode = (els.selectLayoutRenderMode ? els.selectLayoutRenderMode.value : (state.pdf_settings?.layout_render_mode || "image")).toLowerCase();
        const pageSz = (els.selectPageSize ? els.selectPageSize.value : (state.pdf_settings?.page_size || "A3")).toUpperCase().trim();
        if (renderMode === "hybrid") {
          // Для гибридного (векторного) режима подстраиваемся под формат листа (с уменьшением на 30%)
          if (pageSz === "A3") return 0.63;
          return 0.42;
        } else {
          // Для растрового режима расчет идет от разрешения кадра (с уменьшением на 30%)
          const qVal = getEffectiveRenderWidth();
          let mult = 0.60;
          if (qVal <= 1400) mult = 0.60;
          else if (qVal <= 2000) mult = 0.90;
          else if (qVal <= 2800) mult = 1.20;
          else if (qVal <= 3400) mult = 1.50;
          else mult = 1.80;

          // Защитный порог для формата A3
          if (pageSz === "A3") mult = Math.max(mult, 0.90);
          return Math.round(mult * 70) / 100;
        }
      }
      return parseFloat(raw) || 2.0;
    }
    return state.pdf_settings?.scale_factor ? (parseFloat(state.pdf_settings.scale_factor) || 2.0) : 2.0;
  }

  // Navigation Tabs Switching
  function setupTabs() {
    const appContent = document.querySelector(".app-content");
    const tabs = document.querySelectorAll(".tab-btn");
    const tabPanes = document.querySelectorAll(".tab-pane");
    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        flushAutoSave();
        tabs.forEach((t) => t.classList.remove("active"));
        tabPanes.forEach((p) => p.classList.remove("active"));

        tab.classList.add("active");
        if (appContent) {
          appContent.classList.toggle("no-padding", tab.dataset.tab === "tab-scenes" || tab.dataset.tab === "tab-templates");
        }
        const targetPane = document.getElementById(tab.dataset.tab);
        if (targetPane) {
          targetPane.classList.add("active");
          if (tab.dataset.tab === "tab-scenes") {
            renderScenesTable();
            refreshScenesFromModel();
          } else if (tab.dataset.tab === "tab-templates") {
            renderLayoutCanvas();
            renderTemplateSettingsList();
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

  function switchToTab(tabId) {
    flushAutoSave();
    const tabs = document.querySelectorAll(".tab-btn");
    const tabPanes = document.querySelectorAll(".tab-pane");
    const appContent = document.querySelector(".app-content");

    tabs.forEach((t) => {
      if (t.dataset.tab === tabId) {
        t.classList.add("active");
      } else {
        t.classList.remove("active");
      }
    });

    tabPanes.forEach((p) => {
      if (p.id === tabId) {
        p.classList.add("active");
      } else {
        p.classList.remove("active");
      }
    });

    if (appContent) {
      appContent.classList.toggle("no-padding", tabId === "tab-scenes" || tabId === "tab-templates");
    }

    if (tabId === "tab-scenes") {
      renderScenesTable();
      refreshScenesFromModel();
    } else if (tabId === "tab-templates") {
      renderLayoutCanvas();
      renderTemplateSettingsList();
      updateLayoutUsageBadge();
    } else if (tabId === "tab-directories") {
      renderDirectories();
    } else if (tabId === "tab-settings") {
      renderApiTargets();
    }
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

  function flushAutoSave() {
    if (autoSaveTimer) {
      clearTimeout(autoSaveTimer);
      autoSaveTimer = null;
    }
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
      console.error("flushAutoSave error:", err);
      updateAutoSaveIndicator("error", "Ошибка автосохранения");
    }
  }

  function triggerAutoSave() {
    updateAutoSaveIndicator("saving", "Сохранение...");
    clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(() => {
      flushAutoSave();
    }, 400);
  }

  // Notify and keep changes in memory (persisted via debounced autoSave to model attributes and layout.yaml)
  function notifyChange() {
    try {
      if (typeof markDirty === "function") markDirty();
    } catch (err) {}
    triggerAutoSave();
  }

  function isSlotVisible(slotObj, defaultVal = true) {
    if (!slotObj) return defaultVal;
    const v = slotObj.visible;
    if (v === false || v === "false" || v === 0 || v === "0") return false;
    if (v === true || v === "true" || v === 1 || v === "1") return true;
    return defaultVal;
  }

  // -----------------------------------------------------------------------------
  // Fixed Slot Layout Editor Engine
  // -----------------------------------------------------------------------------

  function ensureCustomLayouts() {
    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};

    const validSlotIds = new Set(FIXED_SLOT_DEFS.map((s) => s.id));
    const metaKeys = new Set(["name", "_name", "_base_type", "_icon", "_meta"]);

    const allTplKeys = Array.from(new Set([...Object.keys(DEFAULT_LAYOUTS), ...Object.keys(state.pdf_settings.custom_layouts)]));

    allTplKeys.forEach((tplKey) => {
      if (!state.pdf_settings.custom_layouts[tplKey]) {
        state.pdf_settings.custom_layouts[tplKey] = {};
      }

      // Purge legacy keys (e.g. cover_accent_bar, cover_hero_image, desc_header, etc.), preserving metadata
      Object.keys(state.pdf_settings.custom_layouts[tplKey]).forEach((k) => {
        if (!validSlotIds.has(k) && !metaKeys.has(k)) {
          delete state.pdf_settings.custom_layouts[tplKey][k];
        }
      });

      const baseKey = state.pdf_settings.custom_layouts[tplKey]?._base_type || (DEFAULT_LAYOUTS[tplKey] ? tplKey : "general");
      const tplDefaults = (DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general)?.slots || {};
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
            visible: isSlotVisible(defSlot),
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
          if (current.visible === undefined || current.visible === null) {
            current.visible = defSlot.visible !== false;
          } else {
            current.visible = isSlotVisible(current);
          }
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
            current.line_rows = Object.assign({}, defLineRows, current.line_rows || {});
            current.line_font_sizes = Object.assign({}, defLineFontSizes, current.line_font_sizes || {});
            current.line_colors = Object.assign({}, defLineColors, current.line_colors || {});
          }
          if (slotDef.id === "slot_1") {
            if (!current.content) current.content = defSlot.content || "info_lines";
            if (!current.lines) {
              current.lines = defSlot.lines ? deepClone(defSlot.lines) : deepClone(DEFAULT_MIDDLE_SLOT.lines);
            }
            current.line_aligns = Object.assign({}, defLineAligns || DEFAULT_MIDDLE_ALIGNS, current.line_aligns || {});
            current.line_valigns = Object.assign({}, defLineValigns || DEFAULT_MIDDLE_VALIGNS, current.line_valigns || {});
            current.line_font_sizes = Object.assign({}, defLineFontSizes || DEFAULT_MIDDLE_SIZES, current.line_font_sizes || {});
            current.line_colors = Object.assign({}, defLineColors || DEFAULT_MIDDLE_COLORS, current.line_colors || {});
            if (current.item_gap_mm === undefined && current.item_gap === undefined) {
              current.item_gap_mm = defSlot.item_gap_mm !== undefined ? defSlot.item_gap_mm : 2;
            }
          }
          if (slotDef.id === "footer") {
            current.line_aligns = Object.assign({}, defLineAligns || {}, current.line_aligns || {});
          }
          if (current.opacity === undefined) current.opacity = defSlot.opacity !== undefined ? defSlot.opacity : 0.9;
        }
      });
    });
  }

  // -----------------------------------------------------------------------------
  // Dynamic Template Registry & Management
  // -----------------------------------------------------------------------------
  function getAllTemplates() {
    const builtins = [
      { key: "cover", name: "Титульный лист (Cover)", icon: "🏷️", isDefault: true },
      { key: "description", name: "Описание и спецификации (Description)", icon: "📝", isDefault: true },
      { key: "explain", name: "Содержание и ведомость (Explain)", icon: "📋", isDefault: true },
      { key: "general", name: "Общий вид (General)", icon: "🖼️", isDefault: true },
      { key: "visual", name: "Визуализация (Visual)", icon: "👁️", isDefault: true },
      { key: "blank", name: "Без шаблона (Blank)", icon: "⬜", isDefault: true }
    ];

    const result = [...builtins];
    const customLayouts = state.pdf_settings?.custom_layouts || {};

    Object.keys(customLayouts).forEach((key) => {
      if (!builtins.some((b) => b.key === key)) {
        const tplObj = customLayouts[key];
        const customName = tplObj?._name || tplObj?.name || state.pdf_settings?.template_names?.[key] || `Шаблон (${key})`;
        const customIcon = tplObj?._icon || "📄";
        result.push({
          key: key,
          name: customName,
          icon: customIcon,
          isDefault: false,
          baseType: tplObj?._base_type || "general"
        });
      }
    });

    return result;
  }

  function getTemplateDef(tplKey) {
    if (DEFAULT_LAYOUTS[tplKey]) {
      const iconMap = {
        cover: "🏷️",
        description: "📝",
        explain: "📋",
        general: "🖼️",
        visual: "👁️",
        blank: "⬜"
      };
      return {
        key: tplKey,
        name: DEFAULT_LAYOUTS[tplKey].name,
        icon: iconMap[tplKey] || "📄",
        isDefault: true,
        slots: DEFAULT_LAYOUTS[tplKey].slots || {}
      };
    }
    const customLayouts = state.pdf_settings?.custom_layouts || {};
    const custom = customLayouts[tplKey] || {};
    const baseKey = custom._base_type || "general";
    const baseDef = DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general;
    const name = custom._name || custom.name || state.pdf_settings?.template_names?.[tplKey] || `Шаблон (${tplKey})`;
    const icon = custom._icon || "📄";

    return {
      key: tplKey,
      name: name,
      icon: icon,
      isDefault: false,
      baseType: baseKey,
      slots: baseDef.slots || {}
    };
  }

  function renderTemplatesList() {
    const listEl = els.templatesList || document.getElementById("templatesList");
    if (!listEl) return;
    listEl.innerHTML = "";

    const templates = getAllTemplates();
    const currentKey = layoutState.currentTemplate || "cover";
    const scenes = state.scenes || [];

    templates.forEach((tpl) => {
      const item = document.createElement("div");
      item.className = `template-list-item${tpl.key === currentKey ? " active" : ""}`;
      item.dataset.tpl = tpl.key;

      const matchingScenes = scenes.filter((s) => s.page_type === tpl.key);
      const usageText = matchingScenes.length > 0 
        ? `${matchingScenes.length} ${matchingScenes.length === 1 ? "сцена" : (matchingScenes.length < 5 ? "сцены" : "сцен")}`
        : "не используется";

      const subText = tpl.isDefault ? `По умолчанию • ${usageText}` : `Пользовательский • ${usageText}`;

      const mainDiv = document.createElement("div");
      mainDiv.className = "tpl-item-main";

      const iconSpan = document.createElement("span");
      iconSpan.className = "tpl-item-icon";
      iconSpan.textContent = tpl.icon;

      const textDiv = document.createElement("div");
      textDiv.className = "tpl-item-text";

      const nameSpan = document.createElement("span");
      nameSpan.className = "tpl-item-name";
      nameSpan.textContent = tpl.name;

      const subSpan = document.createElement("span");
      subSpan.className = "tpl-item-sub";
      subSpan.textContent = subText;

      textDiv.appendChild(nameSpan);
      textDiv.appendChild(subSpan);
      mainDiv.appendChild(iconSpan);
      mainDiv.appendChild(textDiv);
      item.appendChild(mainDiv);

      // Actions (for custom templates)
      if (!tpl.isDefault) {
        const actionsDiv = document.createElement("div");
        actionsDiv.className = "tpl-item-actions";

        const btnRename = document.createElement("button");
        btnRename.type = "button";
        btnRename.className = "tpl-item-action-btn";
        btnRename.title = "Переименовать шаблон";
        btnRename.textContent = "✏️";
        btnRename.addEventListener("click", (e) => {
          e.stopPropagation();
          promptRenameTemplate(tpl.key);
        });

        const btnDel = document.createElement("button");
        btnDel.type = "button";
        btnDel.className = "tpl-item-action-btn delete";
        btnDel.title = "Удалить шаблон";
        btnDel.textContent = "🗑️";
        btnDel.addEventListener("click", (e) => {
          e.stopPropagation();
          deleteCustomTemplate(tpl.key);
        });

        actionsDiv.appendChild(btnRename);
        actionsDiv.appendChild(btnDel);
        item.appendChild(actionsDiv);
      }

      item.addEventListener("click", () => {
        selectTemplate(tpl.key);
      });

      listEl.appendChild(item);
    });
  }

  let templatePendingDelete = null;
  let templatePendingRename = null;

  function selectTemplate(tplKey) {
    flushAutoSave();
    layoutState.currentTemplate = tplKey;
    const tplDef = getTemplateDef(tplKey);

    // Если в выбранном шаблоне выключен видовой экран, выключаем оверлей
    const customLayouts = state.pdf_settings ? state.pdf_settings.custom_layouts || {} : {};
    const tplCfg = customLayouts[tplKey] || {};
    const imgCfg = tplCfg.image_4_3 || {};
    const isVis = tplKey !== "blank" && isSlotVisible(imgCfg, true);
    if (!isVis) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = false;
      callRuby("toggleAspectOverlay", false);
    }

    if (els.currentTemplateTitle) {
      els.currentTemplateTitle.textContent = `${tplDef.icon || "📄"} ${tplDef.name}`;
    }

    if (els.selectLayoutTemplate) {
      els.selectLayoutTemplate.value = tplKey;
    }

    const isCustom = !DEFAULT_LAYOUTS[tplKey];
    if (els.btnDeleteCurrentTemplate) {
      els.btnDeleteCurrentTemplate.style.display = isCustom ? "inline-flex" : "none";
    }
    if (els.btnDeleteTemplateSidebar) {
      els.btnDeleteTemplateSidebar.style.display = isCustom ? "inline-flex" : "none";
    }
    if (els.btnRenameCurrentTemplate) {
      els.btnRenameCurrentTemplate.style.display = isCustom ? "inline-flex" : "none";
    }

    renderTemplateSettingsList(true);
    renderTemplatesList();
    updateLayoutUsageBadge();
  }

  function syncTemplateDropdowns() {
    // Update els.selectLayoutTemplate options
    if (els.selectLayoutTemplate) {
      const currentVal = layoutState.currentTemplate;
      els.selectLayoutTemplate.innerHTML = "";
      const templates = getAllTemplates();
      templates.forEach((t) => {
        const opt = document.createElement("option");
        opt.value = t.key;
        opt.textContent = `${t.icon || "📄"} ${t.name}`;
        if (t.key === currentVal) opt.selected = true;
        els.selectLayoutTemplate.appendChild(opt);
      });
    }
  }

  function createCustomTemplate(name, baseKey = "general") {
    if (!name || !name.trim()) return;
    const trimmedName = name.trim();

    ensureCustomLayouts();
    const newKey = "custom_" + Date.now().toString(36);

    const baseDef = DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general;
    const baseSlots = state.pdf_settings.custom_layouts[baseKey] || baseDef.slots || {};

    state.pdf_settings.custom_layouts[newKey] = deepClone(baseSlots);
    state.pdf_settings.custom_layouts[newKey].name = trimmedName;
    state.pdf_settings.custom_layouts[newKey]._name = trimmedName;
    state.pdf_settings.custom_layouts[newKey]._base_type = baseKey;
    state.pdf_settings.custom_layouts[newKey]._icon = "📄";

    if (!state.pdf_settings.template_names) state.pdf_settings.template_names = {};
    state.pdf_settings.template_names[newKey] = trimmedName;

    syncTemplateDropdowns();
    selectTemplate(newKey);
    renderScenesTable();
    notifyChange();
    showNotification(`Шаблон «${trimmedName}» успешно создан`, "success");
  }

  function openDeleteTemplateModal(tplKey) {
    if (!tplKey || DEFAULT_LAYOUTS[tplKey]) {
      showNotification("Стандартные шаблоны нельзя удалить", "warning");
      return;
    }
    templatePendingDelete = tplKey;
    const tplDef = getTemplateDef(tplKey);
    if (els.deleteTemplateMsg) {
      els.deleteTemplateMsg.textContent = `Вы действительно хотите удалить пользовательский шаблон «${tplDef.name}»?`;
    }
    if (els.deleteTemplateModal) {
      els.deleteTemplateModal.classList.remove("hidden");
    }
  }

  function closeDeleteTemplateModal() {
    templatePendingDelete = null;
    if (els.deleteTemplateModal) {
      els.deleteTemplateModal.classList.add("hidden");
    }
  }

  function confirmDeleteTemplate() {
    const tplKey = templatePendingDelete;
    if (!tplKey || DEFAULT_LAYOUTS[tplKey]) {
      closeDeleteTemplateModal();
      return;
    }
    const tplDef = getTemplateDef(tplKey);

    // Reassign scenes
    let reassignedCount = 0;
    (state.scenes || []).forEach((s) => {
      if (s.page_type === tplKey) {
        s.page_type = "general";
        reassignedCount++;
      }
    });

    if (state.pdf_settings?.custom_layouts) {
      delete state.pdf_settings.custom_layouts[tplKey];
    }
    if (state.pdf_settings?.template_names) {
      delete state.pdf_settings.template_names[tplKey];
    }

    closeDeleteTemplateModal();
    layoutState.currentTemplate = "general";
    syncTemplateDropdowns();
    renderTemplatesList();
    renderScenesTable();
    selectTemplate("general");
    notifyChange();
    showNotification(`Шаблон «${tplDef.name}» удален${reassignedCount > 0 ? ` (сцен переключено на Общий вид: ${reassignedCount})` : ""}`, "info");
  }

  function deleteCustomTemplate(tplKey) {
    openDeleteTemplateModal(tplKey);
  }

  function openRenameTemplateModal(tplKey) {
    if (!tplKey || DEFAULT_LAYOUTS[tplKey]) {
      showNotification("Стандартные шаблоны нельзя переименовать", "warning");
      return;
    }
    templatePendingRename = tplKey;
    const tplDef = getTemplateDef(tplKey);
    if (els.inputRenameTemplateName) {
      els.inputRenameTemplateName.value = tplDef.name;
    }
    if (els.renameTemplateModal) {
      els.renameTemplateModal.classList.remove("hidden");
      if (els.inputRenameTemplateName) {
        setTimeout(() => els.inputRenameTemplateName.focus(), 50);
      }
    }
  }

  function closeRenameTemplateModal() {
    templatePendingRename = null;
    if (els.renameTemplateModal) {
      els.renameTemplateModal.classList.add("hidden");
    }
  }

  function confirmRenameTemplate() {
    const tplKey = templatePendingRename;
    if (!tplKey || DEFAULT_LAYOUTS[tplKey]) {
      closeRenameTemplateModal();
      return;
    }
    const newName = els.inputRenameTemplateName ? els.inputRenameTemplateName.value.trim() : "";
    if (!newName) {
      showNotification("Название шаблона не может быть пустым", "warning");
      if (els.inputRenameTemplateName) els.inputRenameTemplateName.focus();
      return;
    }

    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
    if (!state.pdf_settings.custom_layouts[tplKey]) state.pdf_settings.custom_layouts[tplKey] = {};
    state.pdf_settings.custom_layouts[tplKey].name = newName;
    state.pdf_settings.custom_layouts[tplKey]._name = newName;
    if (!state.pdf_settings.template_names) state.pdf_settings.template_names = {};
    state.pdf_settings.template_names[tplKey] = newName;

    closeRenameTemplateModal();
    syncTemplateDropdowns();
    renderTemplatesList();
    renderScenesTable();
    selectTemplate(tplKey);
    notifyChange();
    showNotification(`Шаблон переименован в «${newName}»`, "success");
  }

  function promptRenameTemplate(tplKey) {
    openRenameTemplateModal(tplKey);
  }

  function getActiveLayoutBlocks() {
    ensureCustomLayouts();
    const tplKey = layoutState.currentTemplate || "cover";
    const tplDef = getTemplateDef(tplKey);
    const tplDefaults = tplDef.slots || {};
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
        show_titles: custom.show_titles !== undefined ? custom.show_titles : (defSlot.show_titles !== undefined ? defSlot.show_titles : true),
        line_show_titles: custom.line_show_titles ? Object.assign({}, custom.line_show_titles) : (defSlot.line_show_titles ? Object.assign({}, defSlot.line_show_titles) : null),
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
    const defTpl = getTemplateDef(tplKey);
    const defSlot1 = defTpl.slots?.slot_1 || DEFAULT_MIDDLE_SLOT;
    if (!state.pdf_settings.custom_layouts[tplKey].slot_1) {
      state.pdf_settings.custom_layouts[tplKey].slot_1 = deepClone(defSlot1);
    }
    const s1 = state.pdf_settings.custom_layouts[tplKey].slot_1;
    if (!s1.content) s1.content = defSlot1.content || "info_lines";
    if (!s1.lines) {
      s1.lines = deepClone(defSlot1.lines || DEFAULT_MIDDLE_SLOT.lines);
    }
    if (s1.show_titles === undefined) {
      s1.show_titles = defSlot1.show_titles !== undefined ? defSlot1.show_titles : true;
    }
    if (!s1.line_show_titles) {
      s1.line_show_titles = deepClone(defSlot1.line_show_titles || {});
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
        const lineDef = getInfoLineDef(k);
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
          const lineDef = getInfoLineDef(k);
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
        const lineDef = getInfoLineDef(lineKey);
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

  // Синхронизация оверлея в SketchUp с выбранной сценой/страницей
  function syncCurrentSceneOverlay(scene, overrideRatio, isUserAction = false) {
    if (!scene) {
      const idx = layoutState.selectedSceneIndex || 0;
      scene = (state.scenes || [])[idx];
      if (!scene) return;
    }

    const isVis = scene.viewport_visible !== false;
    if (!isVis) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = false;
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) {
        chkTpl.checked = false;
        chkTpl.disabled = true;
      }
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) tplBadge.classList.add("disabled-overlay");
      if (isUserAction) {
        callRuby("toggleAspectOverlay", false);
      }
      return;
    }

    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "1:1", "custom"];
    let ratio = overrideRatio || scene.aspect_ratio || state.pdf_settings?.image_aspect_ratio || "4:3";
    ratio = String(ratio).trim();
    if (!VALID_ASPECT_RATIOS.includes(ratio)) {
      ratio = "4:3";
    }

    const displayRatio = ratio.toLowerCase() === "page" ? "ПО ЛИСТУ" : ratio.toUpperCase();
    const tplText = document.getElementById("tplAspectOverlayText");
    if (tplText) {
      tplText.textContent = `📐 РАМКА: ${displayRatio}`;
    }
    const tplNote = document.querySelector(".tpl-image-note");
    if (tplNote) {
      tplNote.textContent = `Рамка в окне SketchUp отображает точные границы кадра для текущей страницы с выбранными пропорциями (${displayRatio}).`;
    }

    if (!isUserAction) return;

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A3").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const baseWidth = getEffectiveRenderWidth();

    const borderColor = state.pdf_settings?.overlay_border_color || "#0EA5E9";
    const borderOpacity = state.pdf_settings?.overlay_border_opacity !== undefined ? parseInt(state.pdf_settings.overlay_border_opacity, 10) : 100;
    const maskColor = state.pdf_settings?.overlay_mask_color || "#0F172A";
    const maskOpacity = state.pdf_settings?.overlay_mask_opacity !== undefined ? parseInt(state.pdf_settings.overlay_mask_opacity, 10) : 55;

    const payload = {
      template_key: scene.page_type || "cover",
      scene_name: scene.name || "",
      scene_index: layoutState.selectedSceneIndex || 0,
      aspect_ratio: ratio,
      image_aspect_ratio: ratio,
      visible: isVis,
      scale_pct: scene.scale_pct || 100,
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

  // Синхронизация пропорций кадра и параметров оверлея в SketchUp с блоком "Картинка чертежа" шаблона
  function syncCurrentTemplateOverlay(overrideRatio, isUserAction = false) {
    const idx = layoutState.selectedSceneIndex || 0;
    const scene = (state.scenes || [])[idx];
    if (scene) {
      syncCurrentSceneOverlay(scene, overrideRatio, isUserAction);
      return;
    }

    const tplKey = layoutState.currentTemplate || "cover";
    ensureCustomLayouts();
    const customLayouts = state.pdf_settings ? state.pdf_settings.custom_layouts || {} : {};
    const tplCfg = customLayouts[tplKey] || {};
    const imgCfg = tplCfg.image_4_3 || {};

    const isVis = tplKey !== "blank" && isSlotVisible(imgCfg, true);
    if (!isVis) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = false;
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) {
        chkTpl.checked = false;
        chkTpl.disabled = true;
      }
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) tplBadge.classList.add("disabled-overlay");
      if (isUserAction) {
        callRuby("toggleAspectOverlay", false);
      }
      return;
    }

    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "1:1", "custom"];
    let ratio = overrideRatio || imgCfg.aspect_ratio || state.pdf_settings?.image_aspect_ratio || "4:3";
    ratio = String(ratio).trim();
    if (!VALID_ASPECT_RATIOS.includes(ratio)) {
      ratio = state.pdf_settings?.image_aspect_ratio || "4:3";
      if (!VALID_ASPECT_RATIOS.includes(ratio)) {
        ratio = "4:3";
      }
    }

    const displayRatio = ratio.toLowerCase() === "page" ? "ПО ЛИСТУ" : ratio.toUpperCase();
    const tplText = document.getElementById("tplAspectOverlayText");
    if (tplText) {
      tplText.textContent = `📐 РАМКА: ${displayRatio}`;
    }
    const tplNote = document.querySelector(".tpl-image-note");
    if (tplNote) {
      tplNote.textContent = `Рамка в окне SketchUp отображает точные границы кадра для текущего шаблона с выбранными пропорциями (${displayRatio}).`;
    }

    // Отправка настроек в SketchUp происходит только при явном действии пользователя
    if (!isUserAction) {
      return;
    }

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A3").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const baseWidth = getEffectiveRenderWidth();

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

  function renderTemplateSettingsList(isUserAction = false) {
    if (!els.templateSettingsContainer) return;
    ensureCustomLayouts();
    syncDirectoriesSpecifications();

    const tplKey = layoutState.currentTemplate || "cover";
    const customTpl = state.pdf_settings.custom_layouts[tplKey] || {};
    const tplDefObj = getTemplateDef(tplKey);
    const tplDef = tplDefObj.slots ? tplDefObj : (DEFAULT_LAYOUTS[tplDefObj.baseType] || DEFAULT_LAYOUTS.cover);
    const info = state.project_info || {};
    const wf = state.workflow || {};

    if (els.currentTemplateTitle) {
      els.currentTemplateTitle.textContent = `${tplDefObj.icon || "📄"} ${tplDefObj.name}`;
    }
    const isCustom = !DEFAULT_LAYOUTS[tplKey];
    if (els.btnDeleteCurrentTemplate) {
      els.btnDeleteCurrentTemplate.style.display = isCustom ? "inline-flex" : "none";
    }
    if (els.btnRenameCurrentTemplate) {
      els.btnRenameCurrentTemplate.style.display = isCustom ? "inline-flex" : "none";
    }

    // Page format badge
    const isPortrait = (els.selectPageLayout ? els.selectPageLayout.value : state.pdf_settings?.page_layout) === "portrait";
    const pageSize = (els.selectPageSize ? els.selectPageSize.value : state.pdf_settings?.page_size) || "A3";
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
    const isHeaderVis = isSlotVisible(header);

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
    const isMiddleVis = isSlotVisible(slot1);
    const isTitlesVis = slot1.show_titles !== false;
    const middleFontSize = slot1.font_size !== undefined ? parseFloat(slot1.font_size) : 8;
    const middleItemGap = slot1.item_gap_mm !== undefined ? parseFloat(slot1.item_gap_mm) : (slot1.item_gap !== undefined ? parseFloat(slot1.item_gap) : 2);
    const middleLines = Array.isArray(slot1.lines) ? slot1.lines : (DEFAULT_LINES_BY_CONTENT.slot_1 || []);
    const middleLineAligns = slot1.line_aligns || {};
    const middleLineValigns = slot1.line_valigns || {};
    const middleLineFontSizes = slot1.line_font_sizes || {};
    const middleLineColors = slot1.line_colors || {};
    const middleLineShowTitles = slot1.line_show_titles || {};

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
    const getMidShowTitle = (k, def = isTitlesVis) => {
      return middleLineShowTitles[k] !== undefined ? !!middleLineShowTitles[k] : def;
    };

    const middleAvailableLines = [
      { key: "toc_pages",         label: "📑 Содержание (список страниц)", val: "1. Титул, 2. План" },
      { key: "spec_materials",    label: "🛠️ Материалы и фурнитура",      val: (info.materials || "Фасады МДФ, ЛДСП, Blum...").trim() },
      { key: "spec_appliances",   label: "🔌 Техника и подсветка",        val: [info.appliances, info.lighting].filter(Boolean).map(s => s.trim()).filter(Boolean).join("; ") || "Встраиваемая техника, LED 3000K..." },
      { key: "general_notes",     label: "📝 Общие пояснения",            val: (info.project_description || info.description || info.notes || "Замеры выполнены по факту").trim() },
      { key: "workflow_history",  label: "📜 История правок",             val: (wf.last_edit || info.last_edit || "Корректировка фасадов").trim() },
      { key: "workflow_stadia",   label: "⏱️ Стадия проекта",             val: (Array.isArray(wf.stadia) ? wf.stadia.map(st => Array.isArray(st) ? st[2] : String(st)).join(", ") : String(wf.stadia || wf.status || info.status || "РД")).trim() },
      { key: "workflow_revision", label: "🔢 Ревизия",                   val: String(wf.revision || info.revision || "001").trim() },
      { key: "workflow_version",  label: "🏷️ Версия",                    val: String(wf.version || info.version || "01").trim() },
      { key: "workflow_date",     label: "📅 Дата",                      val: String(wf.date_order || info.date || new Date().toISOString().slice(0, 10)).trim() },
      { key: "articul",           label: "🔖 Артикул проекта",           val: String(info.articul || "CF#...").trim() }
    ];

    // Динамически добавляем описание каждого блока папки (directories) в средний список шаблонов
    if (Array.isArray(state.directories) && state.directories.length > 0) {
      state.directories.forEach((d, idx) => {
        if (!d) return;
        const dTitle = (d.title || getFolderName(d.path) || `Раздел #${idx + 1}`).trim();
        const dDesc = (d.description || "").trim();
        const dKey = `dir_desc_${idx}`;
        middleAvailableLines.push({
          key: dKey,
          label: `📁 ${dTitle}`,
          val: dDesc || "(описание раздела не заполнено)"
        });
      });
      const allSpecs = state.directories.filter(d => d && (d.description || "").trim()).map((d, i) => `${d.title || ("Раздел #" + (i + 1))}: ${(d.description || "").trim()}`).join(" • ");
      if (allSpecs) {
        middleAvailableLines.push({
          key: "dir_specs",
          label: "📁 Все спецификации папок",
          val: allSpecs
        });
      }
    }

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
            <label class="checkbox-label tpl-chk-titles-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin-left: 4px;" title="Выводить заголовки пунктов на листах проекта">
              <input type="checkbox" class="chk-slot-show-titles" data-slot="slot_1" ${isTitlesVis ? 'checked' : ''}>
              <span>Заголовок</span>
            </label>
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin-left: 4px;">
              <input type="checkbox" id="chk_middle_visible" class="chk-slot-visible" data-slot="slot_1" ${isMiddleVis ? 'checked' : ''}>
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
    const isFooterVis = isSlotVisible(footer);

    const sampleRev = String(wf.revision || info.revision || "001").trim();
    const sampleVer = String(wf.version || info.version || "01").trim();
    const sampleArt = String(info.articul || "CF#...").trim();
    const sampleDate = String(wf.last_edit_date || info.date || new Date().toLocaleDateString()).trim();
    const sampleLastEdit = String(wf.last_edit || "Корректировка фасадов").trim();

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
    // FULL TWO-COLUMN ASSEMBLY REPLACED BY SINGLE COLUMN (Заголовок, Средний, Подвал)
    // -------------------------------------------------------------
    html = `
      <div class="tpl-single-column-layout">
        ${cardHeaderHtml}
        ${cardMiddleHtml}
        ${cardFooterHtml}
      </div>
    `;

    els.templateSettingsContainer.innerHTML = html;
    bindTemplateSettingsEvents(tplKey);
    syncCurrentTemplateOverlay(null, isUserAction);
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
      { key: "workflow_history",  label: "📜 История правок",             val: String(wf.last_edit || "Корректировка фасадов").trim() },
      { key: "workflow_stadia",   label: "⏱️ Стадия проекта",             val: (Array.isArray(info.stadia) ? info.stadia.map(st => (st && st.name) ? st.name : String(st)).join(", ") : String(info.stadia || "РД")).trim() },
      { key: "workflow_revision", label: "🔢 Ревизия",                   val: String(wf.revision || "001").trim() },
      { key: "workflow_version",  label: "🏷️ Версия",                    val: String(wf.version || "01").trim() },
      { key: "workflow_date",     label: "📅 Дата",                      val: String(wf.date_order || new Date().toISOString().slice(0, 10)).trim() },
      { key: "articul",           label: "🔖 Артикул проекта",           val: String(info.articul || "CF#...").trim() }
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
        const isVis = Boolean(e.target.checked);
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        updateBlockSlot("header", { visible: isVis }, targetTpl);
        const card = document.getElementById("card_header");
        if (card) {
          card.classList.toggle("disabled-card", !isVis);
          card.classList.toggle("disabled-block", !isVis);
        }
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
        const sId = e.target.dataset.slot || "slot_1";
        const isVis = Boolean(e.target.checked);
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const updates = { visible: isVis };
        if (isVis && (sId === "slot_1" || sId === "slot_2" || sId === "slot_3" || sId === "slot_4")) {
          updates.content = "info_lines";
        }
        if (sId === "slot_1") {
          const s1 = ensureMiddleSlotDefaults(targetTpl);
          s1.visible = isVis;
        }
        updateBlockSlot(sId, updates, targetTpl);
        const blk = (sId === "slot_1" ? document.getElementById("card_middle") : null) || document.getElementById(`block_${sId}`) || document.getElementById("card_middle");
        if (blk) {
          blk.classList.toggle("disabled-block", !isVis);
          blk.classList.toggle("disabled-card", !isVis);
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
        }
        updateBlockSlot("slot_1", { line_aligns: s1.line_aligns, lines: s1.lines, visible: isSlotVisible(s1), content: s1.content || "info_lines" }, targetTpl);
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
        }
        updateBlockSlot("slot_1", { line_valigns: s1.line_valigns, lines: s1.lines, visible: isSlotVisible(s1), content: s1.content || "info_lines" }, targetTpl);
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
        }
        updateBlockSlot("slot_1", { line_font_sizes: s1.line_font_sizes, lines: s1.lines, visible: isSlotVisible(s1), content: s1.content || "info_lines" }, targetTpl);
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
        }
        updateBlockSlot("slot_1", { line_colors: s1.line_colors, lines: s1.lines, visible: isSlotVisible(s1), content: s1.content || "info_lines" }, targetTpl);
        notifyChange();
      };
      inp.addEventListener("input", handleColorChange);
      inp.addEventListener("change", handleColorChange);
    });

    // Middle Block Titles Toggle (Галка "Заголовок" для страниц проекта)
    const chkSlotShowTitles = els.templateSettingsContainer.querySelectorAll(".chk-slot-show-titles");
    chkSlotShowTitles.forEach((chk) => {
      chk.addEventListener("change", (e) => {
        const sId = e.target.dataset.slot || "slot_1";
        const isShown = e.target.checked;
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const s1 = ensureMiddleSlotDefaults(targetTpl);
        s1.show_titles = isShown;
        updateBlockSlot(sId, { show_titles: isShown, content: "info_lines" }, tplKey);
        notifyChange();
      });
    });

    // Footer Visible Toggle
    const chkFtrVis = document.getElementById("chk_footer_visible");
    if (chkFtrVis) {
      chkFtrVis.addEventListener("change", (e) => {
        const isVis = Boolean(e.target.checked);
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        updateBlockSlot("footer", { visible: isVis }, targetTpl);
        const card = document.getElementById("card_footer");
        if (card) {
          card.classList.toggle("disabled-card", !isVis);
          card.classList.toggle("disabled-block", !isVis);
        }
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
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        const customLayouts = state.pdf_settings ? state.pdf_settings.custom_layouts || {} : {};
        const tplCfg = customLayouts[targetTpl] || {};
        const imgCfg = tplCfg.image_4_3 || {};
        if (!isSlotVisible(imgCfg, true) || targetTpl === "blank") {
          e.target.checked = false;
          return;
        }
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
        const isVis = Boolean(e.target.checked);
        const targetTpl = tplKey || layoutState.currentTemplate || "cover";
        updateBlockSlot("image_4_3", { visible: isVis }, targetTpl);
        const card = document.getElementById("card_image");
        if (card) {
          card.classList.toggle("disabled-card", !isVis);
          card.classList.toggle("disabled-block", !isVis);
        }
        const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
        const tplBadge = document.getElementById("tplAspectOverlayBadge");
        if (!isVis) {
          if (chkTpl) {
            chkTpl.checked = false;
            chkTpl.disabled = true;
          }
          if (tplBadge) {
            tplBadge.classList.add("disabled-overlay");
          }
          if (state.pdf_settings) {
            state.pdf_settings.show_aspect_overlay = false;
          }
          if (els.chkShowAspectOverlay) {
            els.chkShowAspectOverlay.checked = false;
          }
          callRuby("toggleAspectOverlay", false);
        } else {
          if (chkTpl) {
            chkTpl.disabled = false;
          }
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
  function renderLayoutCanvas(isUserAction = false) {
    renderTemplateSettingsList(isUserAction);
  }

  // Layout & Template Settings Setup
  function setupLayoutEditor() {
    // Template switcher
    if (els.selectLayoutTemplate) {
      els.selectLayoutTemplate.addEventListener("change", (e) => {
        selectTemplate(e.target.value);
      });
    }

    // Modal and Template Management Buttons
    if (els.btnCreateTemplate) {
      els.btnCreateTemplate.addEventListener("click", () => {
        if (els.newTemplateModal) {
          if (els.inputNewTemplateName) els.inputNewTemplateName.value = "";
          els.newTemplateModal.classList.remove("hidden");
          if (els.inputNewTemplateName) {
            setTimeout(() => els.inputNewTemplateName.focus(), 50);
          }
        }
      });
    }

    if (els.btnCancelNewTemplate) {
      els.btnCancelNewTemplate.addEventListener("click", () => {
        if (els.newTemplateModal) els.newTemplateModal.classList.add("hidden");
      });
    }

    if (els.btnConfirmNewTemplate) {
      els.btnConfirmNewTemplate.addEventListener("click", () => {
        const name = els.inputNewTemplateName ? els.inputNewTemplateName.value.trim() : "";
        const baseType = els.selectNewTemplateBase ? els.selectNewTemplateBase.value : "general";
        if (!name) {
          showNotification("Введите название шаблона", "warning");
          if (els.inputNewTemplateName) els.inputNewTemplateName.focus();
          return;
        }
        createCustomTemplate(name, baseType);
        if (els.newTemplateModal) els.newTemplateModal.classList.add("hidden");
      });
    }

    if (els.inputNewTemplateName) {
      els.inputNewTemplateName.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          if (els.btnConfirmNewTemplate) els.btnConfirmNewTemplate.click();
        } else if (e.key === "Escape") {
          if (els.newTemplateModal) els.newTemplateModal.classList.add("hidden");
        }
      });
    }

    // Delete Template Modal Handlers
    if (els.btnDeleteCurrentTemplate) {
      els.btnDeleteCurrentTemplate.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        openDeleteTemplateModal(tplKey);
      });
    }

    if (els.btnDeleteTemplateSidebar) {
      els.btnDeleteTemplateSidebar.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        openDeleteTemplateModal(tplKey);
      });
    }

    if (els.btnCancelDeleteTemplate) {
      els.btnCancelDeleteTemplate.addEventListener("click", () => {
        closeDeleteTemplateModal();
      });
    }

    if (els.btnConfirmDeleteTemplate) {
      els.btnConfirmDeleteTemplate.addEventListener("click", () => {
        confirmDeleteTemplate();
      });
    }

    // Rename Template Modal Handlers
    if (els.btnRenameCurrentTemplate) {
      els.btnRenameCurrentTemplate.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        openRenameTemplateModal(tplKey);
      });
    }

    if (els.btnCancelRenameTemplate) {
      els.btnCancelRenameTemplate.addEventListener("click", () => {
        closeRenameTemplateModal();
      });
    }

    if (els.btnConfirmRenameTemplate) {
      els.btnConfirmRenameTemplate.addEventListener("click", () => {
        confirmRenameTemplate();
      });
    }

    if (els.inputRenameTemplateName) {
      els.inputRenameTemplateName.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          confirmRenameTemplate();
        } else if (e.key === "Escape") {
          closeRenameTemplateModal();
        }
      });
    }

    // Margin input
    if (els.inputLayoutMargin) {
      els.inputLayoutMargin.addEventListener("change", (e) => {
        const val = parseFloat(e.target.value) || 0;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.margin_mm = val;
        state.pdf_settings.margin = Math.round(((val * 72.0) / 25.4) * 10) / 10;
        notifyChange();
      });
    }

    // Reset Layout Button
    if (els.btnResetLayout) {
      els.btnResetLayout.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        const tplDefObj = getTemplateDef(tplKey);
        const defTpl = DEFAULT_LAYOUTS[tplDefObj.baseType] || DEFAULT_LAYOUTS.cover;
        if (!defTpl) return;

        if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
        const prevMeta = {};
        if (state.pdf_settings.custom_layouts[tplKey]) {
          const cur = state.pdf_settings.custom_layouts[tplKey];
          ["name", "_name", "_base_type", "_icon", "_meta"].forEach((k) => {
            if (cur[k] !== undefined) prevMeta[k] = cur[k];
          });
        }
        state.pdf_settings.custom_layouts[tplKey] = Object.assign({}, prevMeta);

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
            show_titles: defSlot.show_titles !== undefined ? defSlot.show_titles : (slotDef.id === "slot_1" ? true : undefined),
            line_show_titles: defSlot.line_show_titles ? deepClone(defSlot.line_show_titles) : (slotDef.id === "slot_1" ? {} : undefined),
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
        renderTemplatesList();
        showNotification(`Настройки шаблона «${tplDefObj.name}» сброшены к стандартам`, "success");
        notifyChange();
      });
    }

    syncTemplateDropdowns();
    renderTemplatesList();
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

  // Тип проекта (0 — бытовой, 1 — коммерческий). Выбирается один раз при создании
  // артикула (модалка при открытии панели) и после этого не меняется.
  let currentTradeValue = "0";

  function getTradeValue() {
    return currentTradeValue;
  }

  function setTradeValue(val) {
    currentTradeValue = String(val) === "1" ? "1" : "0";
    updateTradeBadge();
    updateCompanyVisibility();
  }

  // Указатель типа в шапке: без артикула тип еще не выбран
  function updateTradeBadge() {
    if (!els.headerTradeBadge) return;
    const hasArticul = articulValue() !== "";
    const isCommercial = currentTradeValue === "1";
    els.headerTradeBadge.textContent = !hasArticul
      ? "Тип не выбран"
      : (isCommercial ? "🏢 Коммерческий" : "🏠 Бытовой");
    els.headerTradeBadge.classList.toggle("trade-unset", !hasArticul);
    els.headerTradeBadge.classList.toggle("trade-commercial", hasArticul && isCommercial);
    els.headerTradeBadge.classList.toggle("trade-household", hasArticul && !isCommercial);
  }

  function updateCompanyVisibility() {
    if (!els.companyFieldGroup) return;
    const isCommercial = getTradeValue() === "1";
    els.companyFieldGroup.style.display = isCommercial ? "flex" : "none";
  }

  function generateArticulLocal(isCommercial) {
    const prefix = isCommercial ? "CF#" : "HF#";
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const hh = String(now.getHours()).padStart(2, '0');
    const mi = String(now.getMinutes()).padStart(2, '0');
    const ss = String(now.getSeconds()).padStart(2, '0');
    return `${prefix}${yy}${mm}${dd}_${hh}${mi}${ss}`;
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

  // Суффикс ревизии, вшитый в текст старых записей истории: "Текст правки (rev. 004)"
  const HISTORY_REV_SUFFIX_RE = /\s*\(rev\.?\s*(\d{1,})\)\s*$/i;

  // Отделяет вшитый номер ревизии от текста правки: { text, rev } (rev — "004")
  function splitRevSuffix(text) {
    const raw = String(text || "");
    const m = raw.match(HISTORY_REV_SUFFIX_RE);
    if (!m) return { text: raw.trim(), rev: "" };
    return { text: raw.replace(HISTORY_REV_SUFFIX_RE, "").trim(), rev: m[1].padStart(3, "0") };
  }

  // Приводит записи истории к канону: чистый текст + отдельные поля ver/rev.
  // Старые записи хранят ревизию в тексте ("... (rev. 004)") — переносим её в поле rev.
  function migrateHistoryEntries(history) {
    (history || []).forEach((item) => {
      if (!item || typeof item !== "object") return;
      item.ver = String(item.ver || "").trim();
      item.rev = String(item.rev || "").trim();
      const clean = splitRevSuffix(item.text || item.edit || item.description || "");
      if (!item.rev && clean.rev) item.rev = clean.rev;
      if (clean.rev) {
        item.text = clean.text;
        item.edit = clean.text;
        item.description = clean.text;
      }
    });
    return history;
  }

  // Populate UI from State
  function renderUI() {
    const prj = state.project || {};
    const cust = state.customer || {};
    const wf = state.workflow || {};
    const info = state.project_info || {};
    const settings = state.pdf_settings || {};

    // Синхронизация истории правок: state.history — основной источник (приходит
    // из Ruby с pdf_link/ver/rev), пары workflow.history_edit — только fallback.
    if ((!Array.isArray(state.history) || state.history.length === 0)
        && Array.isArray(wf.history_edit) && wf.history_edit.length > 0) {
      state.history = wf.history_edit.map((item) => {
        if (Array.isArray(item)) {
          return { date: item[0] || "", text: item[1] || "", description: item[1] || "", pdf_link: item[2] || "", ver: "", rev: "" };
        } else if (item && typeof item === "object") {
          const t = item.text || item.description || "";
          return { date: item.date || "", text: t, description: t, pdf_link: item.pdf_link || "", ver: item.ver || item.version || "", rev: item.rev || item.revision || "" };
        }
        return { date: "", text: String(item || ""), description: String(item || ""), ver: "", rev: "" };
      });
    }
    if (Array.isArray(state.history) && state.history.length > 0) {
      migrateHistoryEntries(state.history);
      // Пары для PDF-инфолиний: чистый текст без номера ревизии
      wf.history_edit = state.history.map((item) => [item.date || "", item.text || item.description || ""]);
    }

    // 1. Паспорт объекта (Project)
    const isCommercial = prj.commercial !== undefined
      ? Boolean(prj.commercial)
      : (info.trade === 1 || info.trade === "1" || (prj.articul || info.articul || "").startsWith("CF#"));

    setTradeValue(isCommercial ? "1" : "0");
    updateCompanyVisibility();

    if (els.inputArticul) els.inputArticul.value = prj.articul || info.articul || "";
    updateTradeBadge();
    if (els.inputCompany) els.inputCompany.value = prj.name_company || info.company || "";
    if (els.inputFurnitureName) {
      const pTags = prj.product_tags || info.product_tags;
      if (Array.isArray(pTags) && pTags.length) {
        els.inputFurnitureName.value = pTags.join(", ");
      } else {
        els.inputFurnitureName.value = prj.product || info.name_product || info.furniture_name || prj.tags || info.tags || "";
      }
    }
    if (els.inputTags) {
      const tagsVal = prj.tags !== undefined ? prj.tags : (info.tags || "");
      els.inputTags.value = Array.isArray(tagsVal) ? tagsVal.join(", ") : String(tagsVal || "");
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

    // LayOut PDF Settings
    if (els.selectLayoutRenderMode) els.selectLayoutRenderMode.value = settings.layout_render_mode || "image";
    if (els.selectCompression) {
      els.selectCompression.value = (settings.compress_pdf === true || settings.compress_pdf === "compress") ? "compress" : "none";
    }
    if (els.selectImageFormat) {
      els.selectImageFormat.value = (settings.image_format || "png").toLowerCase();
    }
    if (els.selectWebpQuality) {
      const webpQ = String(settings.webp_quality ?? "85").toLowerCase();
      els.selectWebpQuality.value = ["75", "85", "95", "lossless"].includes(webpQ) ? webpQ : "85";
    }
    // Формат снимков не настраивается: WebP при доступной libvips, иначе PNG
    if (els.hintWebpFormat) {
      els.hintWebpFormat.textContent = state.vips_available
        ? "libvips доступна — снимки сцен сохраняются в WebP."
        : "libvips не найдена (vendor/libvips) — снимки сцен сохраняются как PNG.";
    }
    if (els.chkSaveLayoutFile) els.chkSaveLayoutFile.checked = settings.save_layout_file !== false;

    if (els.selectPageSize) {
      els.selectPageSize.value = "A3";
    }
    if (els.selectPageLayout) els.selectPageLayout.value = settings.page_layout || "landscape";
    const marginMm = settings.margin_mm !== undefined && settings.margin_mm !== null
      ? parseFloat(settings.margin_mm)
      : (settings.margin !== undefined && settings.margin !== null ? Math.round((parseFloat(settings.margin) * 25.4) / 72.0) : 5);
    if (els.inputPageMargin) els.inputPageMargin.value = marginMm;
    if (els.inputLayoutMargin) els.inputLayoutMargin.value = marginMm;
    let curFontFamily = (settings.font_family || "Sofia Sans Condensed").trim();
    if (curFontFamily.toLowerCase().includes("din")) {
      curFontFamily = "Oswald";
    }
    if (els.selectFontFamily) els.selectFontFamily.value = curFontFamily;
    if (els.selectLayoutFontFamily) els.selectLayoutFontFamily.value = curFontFamily;
    const curFontWeight = String(settings.font_weight || "normal").toLowerCase() === "bold" ? "bold" : "normal";
    const curFontWidth = settings.font_width === "extra_condensed" ? "extra_condensed" : "condensed";
    if (els.selectFontWeight) els.selectFontWeight.value = curFontWeight;
    if (els.selectFontWidth) els.selectFontWidth.value = curFontWidth;
    document.documentElement.style.setProperty("--page-font-family", `"${previewFontFamilyFor(curFontFamily, curFontWidth)}", sans-serif`);
    document.documentElement.style.setProperty("--page-font-weight", curFontWeight === "bold" ? "700" : "400");
    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "1:1", "custom"];
    let initialAspect = settings.image_aspect_ratio;
    if (!VALID_ASPECT_RATIOS.includes(initialAspect)) {
      initialAspect = "4:3";
    }
    if (els.selectImageAspect) els.selectImageAspect.value = initialAspect;
    if (els.inputAspectCustomW) els.inputAspectCustomW.value = settings.custom_ratio_w || 16;
    if (els.inputAspectCustomH) els.inputAspectCustomH.value = settings.custom_ratio_h || 9;
    if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = settings.show_aspect_overlay === true;
    updateAspectUI(false);
    if (els.selectQuality) {
      let qVal = settings.render_quality ? settings.render_quality.toString().toLowerCase().trim() : "";
      if (!["low", "medium", "high"].includes(qVal)) {
        const num = parseInt(settings.image_width, 10);
        if (num <= 1400) qVal = "low";
        else if (num > 2800) qVal = "high";
        else qVal = "medium";
      }
      els.selectQuality.value = qVal;
    }
    if (els.selectScaleMultiplier) {
      let sm = (settings.scale_multiplier !== undefined && settings.scale_multiplier !== null)
        ? String(settings.scale_multiplier)
        : (settings.scale_factor ? String(settings.scale_factor) : "2.0");
      if (sm === "0.5") sm = "0.5";
      else if (sm === "1" || sm === "1.0") sm = "1";
      else if (sm === "1.5") sm = "1.5";
      else if (sm === "2" || sm === "2.0") sm = "2.0";
      else if (sm === "2.5") sm = "2.5";
      else if (sm === "3" || sm === "3.0") sm = "3.0";
      else if (sm === "auto") sm = "auto";
      else sm = "2.0";
      els.selectScaleMultiplier.value = sm;
    }
    if (els.selectAnnotationFontSize) {
      els.selectAnnotationFontSize.value = settings.annotation_font_size || "auto";
    }
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
    ensureCustomLayouts();
    syncTemplateDropdowns();
    renderTemplatesList();
    renderScenesTable();
    renderStadia();
    renderHistoryTable();
    renderDirectories();
    renderApiTargets();
    selectTemplate(layoutState.currentTemplate || "cover");
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

  // Helper: Extract folder basename from directory path
  function getFolderName(pathStr) {
    if (!pathStr || typeof pathStr !== "string") return "";
    const clean = pathStr.replace(/\\/g, "/").replace(/\/+$/, "");
    const segments = clean.split("/").filter(Boolean);
    return segments.length > 0 ? segments[segments.length - 1] : "";
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

  // Синхронизирует спецификации проекта, связывая их с описаниями (description) в каталогах directories
  function syncDirectoriesSpecifications() {
    if (!Array.isArray(state.directories)) return;
    if (!state.project_info) state.project_info = {};

    state.directories.forEach((d) => {
      if (!d || typeof d !== "object") return;
      const pathStr = (d.path || "").toLowerCase();
      const titleStr = (d.title || "").toLowerCase();
      const descVal = (d.description || "").trim();
      const descIsReal = descVal.length > 0 && descVal !== "Дополнительное описание";

      // 1. Материалы и фурнитура
      if (pathStr.includes("материал") || pathStr.includes("фурнитур") ||
          titleStr.includes("материал") || titleStr.includes("фурнитур")) {
        if (descIsReal) {
          state.project_info.materials = descVal;
        } else if ((state.project_info.materials || "").trim()) {
          d.description = state.project_info.materials.trim();
        }
      }
      // 2. Техника и подсветка
      else if (pathStr.includes("техник") || pathStr.includes("подсветк") ||
               titleStr.includes("техник") || titleStr.includes("подсветк")) {
        if (descIsReal) {
          if (!state.project_info.appliances || state.project_info.appliances.trim() === "") {
            state.project_info.appliances = descVal;
          }
          if (!state.project_info.lighting || state.project_info.lighting.trim() === "") {
            state.project_info.lighting = descVal;
          }
        } else {
          const comb = [state.project_info.appliances, state.project_info.lighting].filter(Boolean).map(s => s.trim()).filter(Boolean).join("; ");
          if (comb) d.description = comb;
        }
      }
      // 3. Замеры помещения и ТЗ
      else if (pathStr.includes("замер") || titleStr.includes("замер")) {
        if (descIsReal) {
          state.project_info.task_dimensions = descVal;
        }
      }
      // 4. Инфо заказчика и примечания
      else if (pathStr.includes("инфо") || pathStr.includes("заказчик") ||
               titleStr.includes("инфо") || titleStr.includes("заказчик")) {
        if (descIsReal) {
          state.project_info.notes = descVal;
        }
      }
    });
  }

  let draggedDirIndex = null;

  // Render Project Directories (directories from YAML) as full Cards with Previews
  function renderDirectories() {
    if (!els.directoriesCardsContainer) return;
    els.directoriesCardsContainer.innerHTML = "";
    syncDirectoriesSpecifications();

    // Нормализация к массиву объектов
    if (state.directories && !Array.isArray(state.directories) && typeof state.directories === "object") {
      state.directories = Object.keys(state.directories).map((k) => {
        const v = state.directories[k] || {};
        const p = v.path || "";
        const fn = getFolderName(p);
        return {
          path:        p,
          title:       v.title || fn || k,
          description: v.description || ""
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

      const folderName = getFolderName(d.path);
      if (!d.title && folderName) {
        d.title = folderName;
      }

      // Drag and Drop обработчики для карточки
      card.addEventListener("dragstart", (e) => {
        draggedDirIndex = index;
        card.classList.add("dragging");
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", index.toString());
      });

      card.addEventListener("dragend", () => {
        card.classList.remove("dragging");
        card.setAttribute("draggable", "false");
        draggedDirIndex = null;
        if (els.directoriesCardsContainer) {
          els.directoriesCardsContainer.querySelectorAll(".directory-card").forEach((c) => {
            c.classList.remove("drag-over-top", "drag-over-bottom");
          });
        }
      });

      card.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (draggedDirIndex === null || draggedDirIndex === index) return;

        const rect = card.getBoundingClientRect();
        const relY = e.clientY - rect.top;
        const isTop = relY < rect.height / 2;

        card.classList.toggle("drag-over-top", isTop);
        card.classList.toggle("drag-over-bottom", !isTop);
      });

      card.addEventListener("dragleave", () => {
        card.classList.remove("drag-over-top", "drag-over-bottom");
      });

      card.addEventListener("drop", (e) => {
        e.preventDefault();
        e.stopPropagation();
        card.classList.remove("drag-over-top", "drag-over-bottom");

        if (draggedDirIndex === null || draggedDirIndex === index) return;

        const rect = card.getBoundingClientRect();
        const relY = e.clientY - rect.top;
        const isTop = relY < rect.height / 2;

        let dropIndex = index;
        if (!isTop) {
          dropIndex = index + 1;
        }
        if (draggedDirIndex < dropIndex) {
          dropIndex--;
        }

        const moved = state.directories.splice(draggedDirIndex, 1)[0];
        state.directories.splice(dropIndex, 0, moved);

        renderDirectories();
        notifyChange();
        showNotification(`Раздел «${moved.title || "Папка"}» перемещен на позицию #${dropIndex + 1}`, "info");
      });

      // 1. HEADER — порядок по макету: заголовок, путь (клик — выбрать папку),
      // Обновить; справа — стрелки порядка, ручка перетаскивания и удаление
      const headerDiv = document.createElement("div");
      headerDiv.className = "dir-card-header";

      const headerLeft = document.createElement("div");
      headerLeft.className = "dir-header-left";

      const titleInput = document.createElement("input");
      titleInput.type = "text";
      titleInput.className = "form-control dir-title-input";
      titleInput.value = d.title || folderName || `Папка #${index + 1}`;
      titleInput.placeholder = "Название раздела проекта (например: Материалы и фурнитура)...";
      titleInput.title = "Название блока/раздела (сохраняется в спецификациях)";
      titleInput.addEventListener("input", (e) => {
        d.title = e.target.value;
      });
      titleInput.addEventListener("change", (e) => {
        d.title = e.target.value.trim();
        notifyChange();
      });

      // Путь — мелкий текст справа от заголовка; клик открывает проводник для выбора
      // папки, заголовок при выборе берется из имени конечного каталога (onDirectorySelected)
      const pathText = document.createElement("span");
      pathText.className = "dir-path-text" + (d.path ? "" : " empty");
      pathText.textContent = d.path || "выбрать папку…";
      pathText.title = d.path
        ? `${d.path}\nНажмите, чтобы выбрать другую папку`
        : "Нажмите, чтобы выбрать папку на диске";
      pathText.addEventListener("click", () => {
        callRuby("selectDirectory", index.toString());
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
          if (state.folderFilesByPath && d.path) delete state.folderFilesByPath[d.path];
          scheduleScanTimeout(index, d.path);
          callRuby("getFolderFiles", JSON.stringify({ index: index, path: d.path }));
        } else {
          showNotification("Укажите путь к папке", "warning");
        }
      });

      headerLeft.appendChild(titleInput);
      headerLeft.appendChild(pathText);
      headerLeft.appendChild(btnRefresh);

      const headerRight = document.createElement("div");
      headerRight.className = "dir-header-right";

      // Ручка перетаскивания мышкой — в правой группе, после стрелок
      const dragHandle = document.createElement("div");
      dragHandle.className = "dir-drag-handle";
      dragHandle.innerHTML = "&#x283F;"; // ⠿
      dragHandle.title = "Потяните мышкой для изменения порядка разделов";
      dragHandle.addEventListener("mousedown", () => {
        card.setAttribute("draggable", "true");
      });
      dragHandle.addEventListener("mouseup", () => {
        card.setAttribute("draggable", "false");
      });

      // Кнопка перемещения вверх
      const btnUp = document.createElement("button");
      btnUp.type = "button";
      btnUp.className = "btn-move-dir";
      btnUp.innerHTML = "&#9650;"; // ▲
      btnUp.title = "Поднять раздел выше";
      btnUp.disabled = (index === 0);
      btnUp.addEventListener("click", () => {
        if (index > 0) {
          const item = state.directories.splice(index, 1)[0];
          state.directories.splice(index - 1, 0, item);
          renderDirectories();
          notifyChange();
        }
      });

      // Кнопка перемещения вниз
      const btnDown = document.createElement("button");
      btnDown.type = "button";
      btnDown.className = "btn-move-dir";
      btnDown.innerHTML = "&#9660;"; // ▼
      btnDown.title = "Опустить раздел ниже";
      btnDown.disabled = (index === state.directories.length - 1);
      btnDown.addEventListener("click", () => {
        if (index < state.directories.length - 1) {
          const item = state.directories.splice(index, 1)[0];
          state.directories.splice(index + 1, 0, item);
          renderDirectories();
          notifyChange();
        }
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

      headerRight.appendChild(btnUp);
      headerRight.appendChild(btnDown);
      headerRight.appendChild(dragHandle);
      headerRight.appendChild(btnDelete);

      headerDiv.appendChild(headerLeft);
      headerDiv.appendChild(headerRight);
      card.appendChild(headerDiv);

      // 2. DESCRIPTION SECTION (Описание и спецификация — сразу поле, без шапки)
      const descSection = document.createElement("div");
      descSection.className = "dir-section-desc";

      const descTextarea = document.createElement("textarea");
      descTextarea.className = "form-control dir-desc-textarea";
      descTextarea.rows = 3;
      descTextarea.placeholder = "Спецификация раздела (материалы, фурнитура, техника, размеры, пояснения к заказу)...";
      descTextarea.value = d.description || "";
      descTextarea.addEventListener("input", (e) => {
        d.description = e.target.value;
        syncDirectoriesSpecifications();
        notifyChange();
      });
      descTextarea.addEventListener("change", (e) => {
        d.description = e.target.value;
        syncDirectoriesSpecifications();
        notifyChange();
      });

      descSection.appendChild(descTextarea);
      card.appendChild(descSection);

      // 4. PREVIEWS SECTION (Блок файлов и предпросмотра)
      const previewSection = document.createElement("div");
      previewSection.className = "dir-section-box dir-section-previews";
      previewSection.id = `dirPreviewBlock_${index}`;

      // Размер эскизов папки: small / medium / large (сохраняется в directories[].thumb_size)
      const thumbSize = ["small", "medium", "large"].includes(d.thumb_size) ? d.thumb_size : "medium";
      d.thumb_size = thumbSize;

      const previewHeader = document.createElement("div");
      previewHeader.className = "dir-preview-header";

      const previewTitle = document.createElement("div");
      previewTitle.className = "dir-section-title";
      previewTitle.innerHTML = `
        <span>🖼️ Файлы и предпросмотр в папке:</span>
        <code style="font-size: 11px; color: var(--text-dim); text-transform: none;">${d.path || "(папка не задана)"}</code>`;

      const sizeGroup = document.createElement("div");
      sizeGroup.className = "dir-thumb-size-group";
      [
        { key: "small", label: "S", title: "Мелкие эскизы" },
        { key: "medium", label: "M", title: "Средние эскизы" },
        { key: "large", label: "L", title: "Крупные эскизы" }
      ].forEach((variant) => {
        const sizeBtn = document.createElement("button");
        sizeBtn.type = "button";
        sizeBtn.className = "dir-thumb-size-btn" + (variant.key === thumbSize ? " active" : "");
        sizeBtn.textContent = variant.label;
        sizeBtn.title = variant.title;
        sizeBtn.addEventListener("click", () => {
          if (d.thumb_size === variant.key) return;
          d.thumb_size = variant.key;
          sizeGroup.querySelectorAll(".dir-thumb-size-btn").forEach((b) => b.classList.remove("active"));
          sizeBtn.classList.add("active");
          const gridForSize = document.getElementById(`dirPreviewGrid_${index}`);
          if (gridForSize) {
            gridForSize.classList.remove("thumb-small", "thumb-medium", "thumb-large");
            gridForSize.classList.add(`thumb-${variant.key}`);
          }
          notifyChange();
        });
        sizeGroup.appendChild(sizeBtn);
      });

      const previewRight = document.createElement("div");
      previewRight.className = "dir-preview-header-right";
      const btnOpenFolder = document.createElement("button");
      btnOpenFolder.type = "button";
      btnOpenFolder.className = "dir-open-folder-btn";
      btnOpenFolder.textContent = "↗";
      btnOpenFolder.title = "Открыть папку в проводнике Windows";
      btnOpenFolder.addEventListener("click", () => {
        if (d.path) {
          callRuby("openDirectoryPath", d.path);
        } else {
          showNotification("Папка не выбрана", "warning");
        }
      });
      previewRight.appendChild(btnOpenFolder);
      const previewBadge = document.createElement("span");
      previewBadge.className = "badge badge-tag badge-grid";
      previewBadge.id = `dirFileBadge_${index}`;
      previewBadge.textContent = "Сканирование...";
      previewRight.appendChild(sizeGroup);
      previewRight.appendChild(previewBadge);

      previewHeader.appendChild(previewTitle);
      previewHeader.appendChild(previewRight);
      previewSection.appendChild(previewHeader);

      const previewGrid = document.createElement("div");
      previewGrid.className = `dir-preview-grid thumb-${thumbSize}`;
      previewGrid.id = `dirPreviewGrid_${index}`;
      previewGrid.innerHTML = `<div class="dir-empty-state" style="grid-column: 1 / -1;">Загрузка файлов...</div>`;
      previewSection.appendChild(previewGrid);

      card.appendChild(previewSection);

      // Предотвращение случайного старта drag при клике на текстовые поля и кнопки
      card.querySelectorAll("input, textarea, button").forEach((el) => {
        el.addEventListener("mousedown", (e) => {
          e.stopPropagation();
          card.setAttribute("draggable", "false");
        });
      });

      els.directoriesCardsContainer.appendChild(card);

      // Запрашиваем файлы для папки, если путь указан
      if (d.path) {
        const cached = (state.folderFiles && state.folderFiles[index] && state.folderFiles[index].path === d.path)
          ? state.folderFiles[index]
          : (state.folderFilesByPath ? state.folderFilesByPath[d.path] : null);
        if (cached) {
          state.folderFiles[index] = cached;
          renderDirectoryPreview(index, cached);
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
        callRuby("openFile", file.path);
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

  // Update Aspect Ratio UI & SketchUp Overlay state
  function updateAspectUI(isUserAction = false) {
    let aspectMode = els.selectImageAspect ? els.selectImageAspect.value : "4:3";
    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "1:1", "custom"];
    if (!VALID_ASPECT_RATIOS.includes(aspectMode)) {
      aspectMode = "4:3";
      if (els.selectImageAspect) els.selectImageAspect.value = "4:3";
    }
    if (els.customAspectGroup) {
      els.customAspectGroup.style.display = (aspectMode === "custom") ? "block" : "none";
    }

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A3").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const baseWidth = getEffectiveRenderWidth();

    let ratio = 1.4142;
    let label = "A3 Альбомный";

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

    // Отправка обновленных настроек в SketchUp для оверлея ТОЛЬКО при явном действии пользователя
    if (isUserAction) {
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

    // Refresh previews in layout canvas
    const tplTab = document.getElementById("tab-templates");
    if (tplTab && tplTab.classList.contains("active")) {
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

  // Cache for scene thumbnails from SketchUp: map of scene name / original_name -> base64 dataURL
  const sceneThumbnails = {};
  let requestedSceneThumbnails = false;
  let sceneThumbnailsInFlight = false;

  function requestSceneThumbnails(force) {
    if (sceneThumbnailsInFlight) return;
    if (!force && requestedSceneThumbnails) return;
    requestedSceneThumbnails = true;
    sceneThumbnailsInFlight = true;
    callRuby("getSceneThumbnails");
  }

  // Актуализировать список страниц из модели SketchUp при открытии вкладки
  // «Страницы проекта» (новые страницы добавляются, удалённые убираются),
  // затем перегенерировать эскизы всех сцен
  function refreshScenesFromModel() {
    if (window.sketchup && typeof window.sketchup.refreshScenes === "function") {
      callRuby("refreshScenes");
    } else {
      // Нет моста SketchUp (просмотр HTML в браузере) — просто обновляем эскизы
      requestSceneThumbnails(true);
    }
  }

  // Switch active scene in SketchUp interface
  function switchToSketchupScene(scene, index) {
    if (!scene) return;
    const payload = JSON.stringify({
      index: index !== undefined ? index : 0,
      name: scene.name || "",
      original_name: scene.original_name || ""
    });
    callRuby("selectScene", payload);

    // Рендерим карточку видового экрана для выбранной страницы
    renderSceneViewportCard(index);

    // Если в выбранной странице выключен видовой экран, выключаем оверлей в GUI
    const isVis = scene.viewport_visible !== false;
    if (!isVis) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = false;
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) {
        chkTpl.checked = false;
        chkTpl.disabled = true;
      }
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) tplBadge.classList.add("disabled-overlay");
      callRuby("toggleAspectOverlay", false);
    } else {
      syncCurrentSceneOverlay(scene, null, true);
    }
  }

  // Highlight active scene row in table
  function highlightActiveSceneRow(index) {
    if (!els.scenesTableBody) return;
    const rows = els.scenesTableBody.querySelectorAll("tr");
    rows.forEach((row, idx) => {
      if (idx === index) {
        row.classList.add("selected-scene-row");
      } else {
        row.classList.remove("selected-scene-row");
      }
    });
  }

  // Update aspect ratio badge in scenes table row
  function updateSceneTableAspectCell(index, ratio, isVis) {
    if (!els.scenesTableBody) return;
    const row = els.scenesTableBody.querySelector(`tr[data-index="${index}"]`);
    if (!row) return;
    const cell = row.querySelector(".scene-aspect-cell");
    if (!cell) return;
    const visible = isVis !== undefined ? isVis : true;
    const r = (ratio || "4:3").trim();
    const displayRatio = r === "page" ? "Лист" : r;
    cell.innerHTML = `<span class="badge badge-aspect ${!visible ? 'badge-aspect-disabled' : ''}" title="${visible ? 'Пропорции кадра: ' + displayRatio : 'Видовой экран выключен'}">${visible ? displayRatio : 'Выкл'}</span>`;
  }

  // Create mini page preview element for a scene (3:2 clean image, no blue lines)
  function createMiniPagePreview(scene, index) {
    const tplKey = scene.page_type || "cover";
    const tplDefObj = getTemplateDef(tplKey);
    const tplIcon = tplDefObj.icon || "📄";
    const tplName = tplDefObj.name || tplKey;

    const wrap = document.createElement("div");
    wrap.className = "scene-mini-preview-wrap";

    const thumbBox = document.createElement("div");
    thumbBox.className = "scene-mini-sheet";
    thumbBox.dataset.index = index;
    thumbBox.dataset.template = tplKey;
    thumbBox.title = `Сцена ${index + 1}: ${scene.name || "Сцена"}\nНажмите для перехода к этому виду в SketchUp`;

    // Check if thumbnail exists
    const sceneKey = scene.name || scene.original_name || "";
    const thumbUrl = scene.thumbnail || sceneThumbnails[sceneKey] || sceneThumbnails[scene.original_name] || sceneThumbnails[index];

    if (thumbUrl) {
      const img = document.createElement("img");
      img.src = thumbUrl;
      img.alt = scene.name || "Preview";
      img.className = "mini-sheet-img";
      thumbBox.appendChild(img);
    } else {
      const placeholder = document.createElement("div");
      placeholder.className = "mini-sheet-placeholder";
      placeholder.innerHTML = `<span class="mini-sheet-placeholder-icon">🖼️</span>`;
      thumbBox.appendChild(placeholder);
    }

    // Click on thumbnail switches scene in SketchUp (stays on current tab)
    thumbBox.addEventListener("click", (e) => {
      e.stopPropagation();
      layoutState.selectedSceneIndex = index;
      selectTemplate(scene.page_type || "cover");
      highlightActiveSceneRow(index);
      switchToSketchupScene(scene, index);
      renderSceneViewportCard(index);
    });

    wrap.appendChild(thumbBox);
    return wrap;
  }

  // Update existing scene preview sheets in table without re-rendering inputs
  function updateSceneTablePreviews() {
    if (!els.scenesTableBody) return;
    const rows = els.scenesTableBody.querySelectorAll("tr");
    rows.forEach((row) => {
      const idx = parseInt(row.dataset.index, 10);
      const scene = (state.scenes || [])[idx];
      if (scene) {
        const cell = row.querySelector(".scene-preview-cell");
        if (cell) {
          cell.innerHTML = "";
          cell.appendChild(createMiniPagePreview(scene, idx));
        }
      }
    });
  }

  // -------------------------------------------------------------
  // RENDER SCENE VIEWPORT & SAFE FRAME CARD (Настройка видового экрана выбранной страницы)
  // -------------------------------------------------------------
  function renderSceneViewportCard(sceneIndex) {
    const container = document.getElementById("sceneViewportSection");
    if (!container) return;

    const scenes = state.scenes || [];
    const idx = (sceneIndex !== undefined && sceneIndex >= 0 && sceneIndex < scenes.length)
      ? sceneIndex
      : (layoutState.selectedSceneIndex || 0);

    const scene = scenes[idx];
    if (!scene) {
      container.innerHTML = `
        <div class="scene-viewport-empty">
          <span style="color: #64748b; font-size: 11px;">Выберите страницу в таблице выше для настройки видового экрана</span>
        </div>
      `;
      return;
    }

    const isImageVis = scene.viewport_visible !== false;
    const VALID_ASPECTS = ["3:2", "4:3", "16:9", "1:1", "page"];
    let rawRatio = (scene.aspect_ratio || state.pdf_settings?.image_aspect_ratio || "4:3").trim();
    const imageAspectRatio = VALID_ASPECTS.includes(rawRatio) ? rawRatio : "4:3";
    const displayAspect = imageAspectRatio.toLowerCase() === "page" ? "ПО ЛИСТУ" : imageAspectRatio.toUpperCase();
    const imageScalePct = parseInt(scene.scale_pct !== undefined ? scene.scale_pct : 100, 10) || 100;
    const isOverlayOn = isImageVis && Boolean(state.pdf_settings && state.pdf_settings.show_aspect_overlay);
    const rawBorderColor = (state.pdf_settings && state.pdf_settings.overlay_border_color) || "#0EA5E9";
    const overlayBorderColor = rawBorderColor.startsWith("#") ? rawBorderColor : `#${rawBorderColor}`;
    const overlayBorderOpacity = state.pdf_settings && state.pdf_settings.overlay_border_opacity !== undefined ? parseInt(state.pdf_settings.overlay_border_opacity, 10) : 100;
    const rawMaskColor = (state.pdf_settings && state.pdf_settings.overlay_mask_color) || "#0F172A";
    const overlayMaskColor = rawMaskColor.startsWith("#") ? rawMaskColor : `#${rawMaskColor}`;
    const rawMaskOpacity = state.pdf_settings && state.pdf_settings.overlay_mask_opacity !== undefined ? parseInt(state.pdf_settings.overlay_mask_opacity, 10) : 70;
    const MASK_PRESETS = [10, 40, 70, 90];
    const overlayMaskOpacity = MASK_PRESETS.reduce((prev, curr) => Math.abs(curr - rawMaskOpacity) < Math.abs(prev - rawMaskOpacity) ? curr : prev, 70);
    const safeSceneName = String(scene.name || `Сцена ${idx + 1}`).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    const cardImageHtml = `
      <div class="tpl-card tpl-panel-left scene-viewport-card ${!isImageVis ? 'disabled-card disabled-block' : ''}" id="card_image">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon">🖼️</span>
            <span class="tpl-card-title">Картинка чертежа под текст (Видовой экран 3D) • Сцена ${idx + 1}: «${safeSceneName}»</span>
          </div>
          <div class="tpl-card-header-actions" style="display: flex; align-items: center; gap: 12px;">
            <label class="tpl-overlay-toggle-btn ${isOverlayOn ? 'active' : ''} ${!isImageVis ? 'disabled-overlay' : ''}" id="tplAspectOverlayBadge" title="Отображать рамку кадра в окне SketchUp (Safe Frame Overlay)" style="margin: 0; cursor: pointer;">
              <input type="checkbox" id="chk_tpl_aspect_overlay" ${isOverlayOn ? 'checked' : ''} ${!isImageVis ? 'disabled' : ''} style="display: none;">
              <span id="tplAspectOverlayText">📐 Рамка: ${displayAspect}</span>
            </label>
            <label class="checkbox-label" style="font-size: 11px; font-weight: 700; cursor: pointer; margin: 0;">
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
          </div>

          <div class="tpl-overlay-styling-row">
            <div class="tpl-overlay-style-item" title="Цвет контурной рамки в окне SketchUp">
              <span class="tpl-overlay-style-label">Контур рамки:</span>
              <div class="tpl-color-picker-wrap">
                <input type="color" id="input_overlay_border_color" value="${overlayBorderColor}" class="tpl-color-picker">
                <span class="tpl-color-hex" id="val_overlay_border_color">${overlayBorderColor}</span>
              </div>
            </div>

            <div class="tpl-overlay-style-item" title="Степень затемнения вне кадра (10%, 40%, 70%, 90%)">
              <span class="tpl-overlay-style-label">Затемнение:</span>
              <div class="tpl-btn-group" id="grp_overlay_mask_opacity">
                <button type="button" class="tpl-btn-align btn-mask-opacity ${overlayMaskOpacity === 10 ? 'active' : ''}" data-opacity="10" title="Легкое затемнение 10%">10%</button>
                <button type="button" class="tpl-btn-align btn-mask-opacity ${overlayMaskOpacity === 40 ? 'active' : ''}" data-opacity="40" title="Умеренное затемнение 40%">40%</button>
                <button type="button" class="tpl-btn-align btn-mask-opacity ${overlayMaskOpacity === 70 ? 'active' : ''}" data-opacity="70" title="Стандартное затемнение 70%">70%</button>
                <button type="button" class="tpl-btn-align btn-mask-opacity ${overlayMaskOpacity === 90 ? 'active' : ''}" data-opacity="90" title="Плотное затемнение 90%">90%</button>
              </div>
            </div>
          </div>

          <p class="tpl-image-note">
            Рамка в окне SketchUp отображает точные границы кадра для текущей страницы с выбранными пропорциями (${displayAspect}).
          </p>
        </div>
      </div>
    `;

    container.innerHTML = cardImageHtml;
    bindSceneViewportEvents(scene, idx);
  }

  function bindSceneViewportEvents(scene, sceneIndex) {
    if (!scene) return;

    const chkVis = document.getElementById("chk_image_4_3_visible");
    if (chkVis) {
      chkVis.addEventListener("change", (e) => {
        const isVis = e.target.checked;
        scene.viewport_visible = isVis;
        updateBlockSlot("image_4_3", { visible: isVis });

        const card = document.getElementById("card_image");
        if (card) {
          card.classList.toggle("disabled-card", !isVis);
          card.classList.toggle("disabled-block", !isVis);
        }
        const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
        const tplBadge = document.getElementById("tplAspectOverlayBadge");
        if (!isVis) {
          if (chkTpl) {
            chkTpl.checked = false;
            chkTpl.disabled = true;
          }
          if (tplBadge) {
            tplBadge.classList.add("disabled-overlay");
          }
          if (state.pdf_settings) {
            state.pdf_settings.show_aspect_overlay = false;
          }
          if (els.chkShowAspectOverlay) {
            els.chkShowAspectOverlay.checked = false;
          }
          callRuby("toggleAspectOverlay", false);
        } else {
          if (chkTpl) chkTpl.disabled = false;
          syncCurrentSceneOverlay(scene, null, true);
        }
        updateSceneTableAspectCell(sceneIndex, scene.aspect_ratio, isVis);
        notifyChange();
      });
    }

    const grpRatio = document.getElementById("grp_image_aspect_ratio");
    if (grpRatio) {
      grpRatio.querySelectorAll(".btn-aspect-ratio").forEach((btn) => {
        btn.addEventListener("click", () => {
          const ratio = btn.dataset.ratio;
          grpRatio.querySelectorAll(".btn-aspect-ratio").forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          scene.aspect_ratio = ratio;
          updateBlockSlot("image_4_3", { aspect_ratio: ratio });
          updateSceneTableAspectCell(sceneIndex, ratio, scene.viewport_visible !== false);
          const tplAspectText = document.getElementById("tplAspectOverlayText");
          if (tplAspectText) {
            const disp = ratio.toLowerCase() === "page" ? "ПО ЛИСТУ" : ratio.toUpperCase();
            tplAspectText.textContent = `📐 Рамка: ${disp}`;
          }
          syncCurrentSceneOverlay(scene, ratio, true);
          notifyChange();
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
          scene.scale_pct = scale;
          updateBlockSlot("image_4_3", { scale_pct: scale });
          syncCurrentSceneOverlay(scene, null, true);
          notifyChange();
        });
      });
    }

    const chkOverlay = document.getElementById("chk_tpl_aspect_overlay");
    if (chkOverlay) {
      chkOverlay.addEventListener("change", (e) => {
        const isChecked = e.target.checked;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.show_aspect_overlay = isChecked;
        if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = isChecked;
        const tplBadge = document.getElementById("tplAspectOverlayBadge");
        if (tplBadge) {
          tplBadge.classList.toggle("active", isChecked);
          tplBadge.classList.toggle("disabled-overlay", !isChecked);
        }
        callRuby("toggleAspectOverlay", isChecked);
        if (isChecked) {
          syncCurrentSceneOverlay(scene, null, true);
        }
        notifyChange();
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
        syncCurrentSceneOverlay(scene, null, true);
        notifyChange();
      };
      inpBorderColor.addEventListener("input", onBorderColorChange);
      inpBorderColor.addEventListener("change", onBorderColorChange);
    }

    const grpMaskOpacity = document.getElementById("grp_overlay_mask_opacity");
    if (grpMaskOpacity) {
      grpMaskOpacity.querySelectorAll(".btn-mask-opacity").forEach((btn) => {
        btn.addEventListener("click", () => {
          grpMaskOpacity.querySelectorAll(".btn-mask-opacity").forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          const opacity = parseInt(btn.dataset.opacity, 10) || 70;
          if (!state.pdf_settings) state.pdf_settings = {};
          state.pdf_settings.overlay_mask_opacity = opacity;
          if (els.inputOverlayMaskOpacity) els.inputOverlayMaskOpacity.value = opacity;
          if (els.overlayMaskOpacityVal) els.overlayMaskOpacityVal.textContent = `${opacity}%`;
          syncCurrentSceneOverlay(scene, null, true);
          notifyChange();
        });
      });
    }

    const inpBorderOpacity = document.getElementById("input_overlay_border_opacity");
    if (inpBorderOpacity) {
      const onBorderOpacityChange = (e) => {
        const val = parseInt(e.target.value, 10) || 100;
        const lbl = document.getElementById("val_overlay_border_opacity");
        if (lbl) lbl.textContent = `${val}%`;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_border_opacity = val;
        syncCurrentSceneOverlay(scene, null, true);
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
        syncCurrentSceneOverlay(scene, null, true);
        notifyChange();
      };
      inpMaskColor.addEventListener("input", onMaskColorChange);
      inpMaskColor.addEventListener("change", onMaskColorChange);
    }

    const inpMaskOpacity = document.getElementById("input_overlay_mask_opacity");
    if (inpMaskOpacity) {
      const onMaskOpacityChange = (e) => {
        const val = parseInt(e.target.value, 10) || 80;
        const lbl = document.getElementById("val_overlay_mask_opacity");
        if (lbl) lbl.textContent = `${val}%`;
        if (!state.pdf_settings) state.pdf_settings = {};
        state.pdf_settings.overlay_mask_opacity = val;
        syncCurrentSceneOverlay(scene, null, true);
        notifyChange();
      };
      inpMaskOpacity.addEventListener("input", onMaskOpacityChange);
      inpMaskOpacity.addEventListener("change", onMaskOpacityChange);
    }
  }

  // Render Scenes Table
  function renderScenesTable() {
    els.scenesTableBody.innerHTML = "";
    const scenes = state.scenes || [];
    updateSceneBadge();

    // Синхронизация глобальной галки фона в тулбаре со состоянием сцен
    if (els.chkScenesBackground) {
      els.chkScenesBackground.checked = scenes.some((s) => s.viewport_background === true);
    }

    scenes.forEach((scene, index) => {
      const tr = document.createElement("tr");
      tr.setAttribute("draggable", "true");
      tr.dataset.index = index;

      if (scene.page_type === layoutState.currentTemplate) {
        tr.classList.add("active-split-scene");
      }
      if (layoutState.selectedSceneIndex === index) {
        tr.classList.add("selected-scene-row");
      }

      // 1. Checkbox (Вкл)
      const tdCheck = document.createElement("td");
      tdCheck.className = "scene-check-cell";

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
      tdCheck.appendChild(chk);

      // 2. Order & Drag Handle (Перемещение и номер)
      const tdNum = document.createElement("td");
      tdNum.className = "scene-num-cell";
      tdNum.title = "Перетащите строку мышью для изменения порядка";

      const numRow = document.createElement("div");
      numRow.className = "scene-num-row";
      const dragHandle = document.createElement("span");
      dragHandle.className = "drag-handle";
      dragHandle.textContent = "⠿";
      dragHandle.title = "Перетащите мышью для изменения порядка";
      const rowNum = document.createElement("span");
      rowNum.className = "row-num";
      rowNum.textContent = index + 1;
      numRow.appendChild(dragHandle);
      numRow.appendChild(rowNum);
      tdNum.appendChild(numRow);

      // 3. Mini Preview of Page (Мини превью страницы)
      const tdPreview = document.createElement("td");
      tdPreview.className = "scene-preview-cell";
      tdPreview.appendChild(createMiniPagePreview(scene, index));

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
      inputName.addEventListener("focus", () => {
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });
      inputName.addEventListener("input", (e) => {
        scene.name = e.target.value;
        renderLayoutCanvas();
      });
      inputName.addEventListener("change", (e) => {
        scene.name = e.target.value.trim();
        e.target.value = scene.name;
        renderTemplateSettingsList();
        updateLayoutUsageBadge();
        renderSceneViewportCard(index);
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
      inputDesc.addEventListener("focus", () => {
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });
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

      // 4. Aspect Ratio Cell (Кадр)
      const tdAspect = document.createElement("td");
      tdAspect.className = "scene-aspect-cell";
      const aspectBadge = document.createElement("span");
      aspectBadge.className = "badge badge-aspect";
      const isVpVis = scene.viewport_visible !== false;
      const curRatio = (scene.aspect_ratio || "4:3").trim();
      const displayRatio = curRatio === "page" ? "Лист" : curRatio;
      aspectBadge.textContent = isVpVis ? displayRatio : "Выкл";
      aspectBadge.title = isVpVis ? `Пропорции кадра: ${displayRatio}` : "Видовой экран выключен";
      if (!isVpVis) aspectBadge.classList.add("badge-aspect-disabled");
      tdAspect.appendChild(aspectBadge);

      // 5. Page Type Select
      const tdType = document.createElement("td");
      tdType.className = "scene-type-cell";
      const typeWrap = document.createElement("div");
      typeWrap.className = "scene-template-cell-wrap";

      const selType = document.createElement("select");
      selType.className = "table-select";
      const allTemplates = getAllTemplates();
      allTemplates.forEach((t) => {
        const opt = document.createElement("option");
        opt.value = t.key;
        opt.textContent = `${t.icon || "📄"} ${t.name}`;
        if (scene.page_type === t.key) opt.selected = true;
        selType.appendChild(opt);
      });
      if (scene.page_type && !allTemplates.some((t) => t.key === scene.page_type)) {
        const opt = document.createElement("option");
        opt.value = scene.page_type;
        opt.textContent = scene.page_type;
        opt.selected = true;
        selType.appendChild(opt);
      }
      selType.addEventListener("focus", () => {
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });
      selType.addEventListener("change", (e) => {
        scene.page_type = e.target.value;
        layoutState.selectedSceneIndex = index;
        updateSceneBadge();
        selectTemplate(e.target.value);
        updateLayoutUsageBadge();
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
        const prevCell = tr.querySelector(".scene-preview-cell");
        if (prevCell) {
          prevCell.innerHTML = "";
          prevCell.appendChild(createMiniPagePreview(scene, index));
        }
        notifyChange();
      });
      selType.addEventListener("click", (e) => e.stopPropagation());

      const btnEditTpl = document.createElement("button");
      btnEditTpl.type = "button";
      btnEditTpl.className = "btn-goto-template";
      btnEditTpl.title = "Перейти к настройке этого шаблона страницы";
      btnEditTpl.textContent = "⚙️";
      btnEditTpl.addEventListener("click", (e) => {
        e.stopPropagation();
        layoutState.selectedSceneIndex = index;
        selectTemplate(scene.page_type || "cover");
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
        switchToTab("tab-templates");
      });

      typeWrap.appendChild(selType);
      typeWrap.appendChild(btnEditTpl);
      tdType.appendChild(typeWrap);

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
          const tplTab = document.getElementById("tab-templates");
          if (tplTab && tplTab.classList.contains("active")) {
            renderLayoutCanvas();
          }
          notifyChange();
        }
      });

      // Click on row to focus template, select scene, and switch SketchUp scene
      tr.addEventListener("click", () => {
        const tpl = scene.page_type || "cover";
        layoutState.selectedSceneIndex = index;
        selectTemplate(tpl);
        updateLayoutUsageBadge();
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });

      tr.appendChild(tdCheck);
      tr.appendChild(tdNum);
      tr.appendChild(tdPreview);
      tr.appendChild(tdInfo);
      tr.appendChild(tdAspect);
      tr.appendChild(tdType);

      els.scenesTableBody.appendChild(tr);
    });

    updateLayoutUsageBadge();
    renderSceneViewportCard(layoutState.selectedSceneIndex || 0);

    // Trigger thumbnail generation from SketchUp if not done yet
    if (!requestedSceneThumbnails && window.sketchup && typeof window.sketchup.getSceneThumbnails === "function") {
      requestSceneThumbnails();
    }
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

        // Обновляем текущий статус по последней отмеченной стадии
        const lastChecked = [...stadia].reverse().find(s => s.status);
        if (lastChecked) {
          state.workflow = state.workflow || {};
          state.workflow.status = lastChecked.name;
          if (state.project_info) state.project_info.status = lastChecked.name;
        }
        if (lastChecked && els.inputStatus) {
          const opts = Array.from(els.inputStatus.options).map(o => o.value);
          if (opts.includes(lastChecked.name)) {
            els.inputStatus.value = lastChecked.name;
          }
        }
        notifyChange();
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

      // 1. Дата и время (data / date) — только чтение, проставляется автоматически
      const tdDate = document.createElement("td");
      tdDate.className = "history-date-cell font-mono";
      const dateStr = item.data || item.date || "";
      tdDate.textContent = dateStr;
      tdDate.title = "Дата и время проставляются автоматически";

      // 2. Версия # Ревизия (ver / rev) — только чтение
      const tdRev = document.createElement("td");
      tdRev.className = "history-rev-cell font-mono";
      const verStr = String(item.ver || "").trim();
      const revStr = String(item.rev || "").trim();
      tdRev.textContent = `${verStr || "—"} # ${revStr || "—"}`;
      tdRev.title = revStr
        ? `Версия ${verStr || "—"} # Ревизия ${revStr}`
        : "Ревизия не назначена (запись без экспорта)";

      // 3. Название правки (edit / text)
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

      // 4. Открыть привязанный PDF (виден путь в подсказке; активна, когда ссылка есть)
      const tdOpen = document.createElement("td");
      tdOpen.className = "history-action-cell";
      const btnOpenPdf = document.createElement("button");
      btnOpenPdf.className = "btn btn-xs btn-secondary";
      btnOpenPdf.textContent = "Открыть";
      const pdfLink = (item.pdf_link || "").trim();
      btnOpenPdf.disabled = !pdfLink;
      btnOpenPdf.title = pdfLink ? `Открыть PDF: ${pdfLink}` : "PDF ещё не создан для этой правки";
      btnOpenPdf.addEventListener("click", () => {
        const link = (item.pdf_link || "").trim();
        if (link) callRuby("openFile", link);
      });
      tdOpen.appendChild(btnOpenPdf);

      // 5. Удаление
      const tdDelete = document.createElement("td");
      tdDelete.className = "history-action-cell";
      const btnDel = document.createElement("button");
      btnDel.className = "btn btn-xs btn-danger";
      btnDel.textContent = "Удалить";
      btnDel.title = "Удалить запись";
      btnDel.addEventListener("click", () => {
        state.history.splice(index, 1);
        renderHistoryTable();
        notifyChange();
      });
      tdDelete.appendChild(btnDel);

      tr.appendChild(tdDate);
      tr.appendChild(tdRev);
      tr.appendChild(tdDesc);
      tr.appendChild(tdOpen);
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
    const isCommercial = getTradeValue() === "1";
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

    // Статус определяется по последней активной стадии
    const activeStadia = (state.workflow?.stadia || []).filter(s => s.status);
    const statusVal = activeStadia.length ? activeStadia[activeStadia.length - 1].name : (state.workflow?.status || "Предварительный");

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
      articul_locked: articulVal !== "",
      product_tags: productTags,
      product: furniture,
      place: room,
      adress: addrVal,
      description: descVal,
      tags: productTags,
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
      version: String(verVal),
      revision: String(revVal),
      stadia: state.workflow?.stadia || [],
      history_edit: historyEditPairs
    };

    // Модуль 4: Корневой history_edit (project.yaml) — с версией/ревизией записи
    state.history_edit = (state.history || []).map((item) => ({
      data: item.data || item.date || "",
      edit: item.edit || item.text || item.description || "",
      pdf_link: item.pdf_link || "",
      ver: item.ver || "",
      rev: item.rev || ""
    }));

    // Фасад project_info для 100% обратной совместимости
    state.project_info = {
      articul:          articulVal,
      articul_locked:   articulVal !== "",
      name_product:     furniture,
      name_place:       room,
      adress:           addrVal,
      customer:         custVal,
      company:          compVal,
      status:           statusVal,
      revision:         String(revVal),
      version:          String(verVal),
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
      layout_render_mode: els.selectLayoutRenderMode ? els.selectLayoutRenderMode.value : "image",
      compress_pdf: els.selectCompression ? (els.selectCompression.value === "compress") : (state.pdf_settings?.compress_pdf === true),
      image_format: els.selectImageFormat ? els.selectImageFormat.value : (state.pdf_settings?.image_format || "png"),
      webp_quality: els.selectWebpQuality ? els.selectWebpQuality.value : (state.pdf_settings?.webp_quality ?? 85),
      save_layout_file: els.chkSaveLayoutFile ? els.chkSaveLayoutFile.checked : true,
      page_size: "A3",
      page_layout: els.selectPageLayout.value,
      margin_mm: els.inputPageMargin ? parseFloat(els.inputPageMargin.value) || 0 : (state.pdf_settings?.margin_mm ?? 5),
      margin: Math.round((((els.inputPageMargin ? parseFloat(els.inputPageMargin.value) || 0 : (state.pdf_settings?.margin_mm ?? 5)) * 72.0) / 25.4) * 10) / 10,
      image_aspect_ratio: els.selectImageAspect ? els.selectImageAspect.value : (state.pdf_settings?.image_aspect_ratio || "4:3"),
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
      render_quality: els.selectQuality ? els.selectQuality.value : (state.pdf_settings?.render_quality || "medium"),
      image_width: getEffectiveRenderWidth(),
      scale_multiplier: els.selectScaleMultiplier ? els.selectScaleMultiplier.value : (state.pdf_settings?.scale_multiplier || "2.0"),
      scale_factor: getEffectiveScaleMultiplier(),
      annotation_font_size: els.selectAnnotationFontSize ? els.selectAnnotationFontSize.value : (state.pdf_settings?.annotation_font_size || "auto"),
      stamp_type: els.selectStamp ? els.selectStamp.value : (state.pdf_settings?.stamp_type || "none"),
      stamp_custom: els.inputCustomStamp ? els.inputCustomStamp.value.trim() : (state.pdf_settings?.stamp_custom || ""),
      font_family: (els.selectFontFamily && els.selectFontFamily.value)
        ? els.selectFontFamily.value
        : (els.selectLayoutFontFamily && els.selectLayoutFontFamily.value
          ? els.selectLayoutFontFamily.value
          : (state.pdf_settings?.font_family || "Sofia Sans Condensed")),
      font_weight: (els.selectFontWeight && els.selectFontWeight.value)
        ? els.selectFontWeight.value
        : (state.pdf_settings?.font_weight || "normal"),
      font_width: (els.selectFontWidth && els.selectFontWidth.value)
        ? els.selectFontWidth.value
        : (state.pdf_settings?.font_width || "condensed"),
      primary_color: els.inputPrimaryColor ? els.inputPrimaryColor.value.replace("#", "") : (state.pdf_settings?.primary_color || "005EB0"),
      stamp_color: els.inputStampColor ? els.inputStampColor.value.replace("#", "") : (state.pdf_settings?.stamp_color || "D32F2F"),
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

  // --- Артикул ---
  // Артикул создаётся один раз (модалка при открытии панели или ввод перед
  // сохранением) и дальше не редактируется и не меняется.

  // Текущее значение артикула из формы
  function articulValue() {
    return (els.inputArticul ? els.inputArticul.value : "").trim();
  }

  // --- Предложение создать артикул при открытии панели экспорта ---
  // Показывается, если проект еще без артикула; выбор типа (коммерческий/бытовой)
  // генерирует артикул и сразу создает папку проекта рядом с рабочим файлом
  function maybeOfferArticulCreation() {
    if (!els.articulTypeModal) return;
    if (!els.articulTypeModal.classList.contains("hidden")) return;
    if (articulValue()) return;
    els.articulTypeModal.classList.remove("hidden");
  }

  function closeArticulTypeModal() {
    if (els.articulTypeModal) els.articulTypeModal.classList.add("hidden");
  }

  // Генерирует артикул выбранного типа и создает папку проекта (Ruby-колбэк)
  function createProjectArticul(isCommercial) {
    const newArt = generateArticulLocal(isCommercial);
    if (els.inputArticul) els.inputArticul.value = newArt;
    setTradeValue(isCommercial ? "1" : "0");
    updateHeaderTitles();
    closeArticulTypeModal();
    callRuby("createProjectFolder", JSON.stringify({ articul: newArt, commercial: isCommercial }));
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

    if (els.btnGenerateCustomerId) {
      els.btnGenerateCustomerId.addEventListener("click", triggerGenerateCustomerId);
    }

    // Directories Add button
    if (els.btnAddDirectory) {
      els.btnAddDirectory.addEventListener("click", () => {
        if (!Array.isArray(state.directories)) state.directories = [];
        const nextNum = state.directories.length + 1;
        state.directories.push({
          path: "",
          title: `Раздел #${nextNum}`,
          description: "Дополнительное описание"
        });
        renderDirectories();
        notifyChange();
        const newIndex = state.directories.length - 1;
        if (els.directoriesCardsContainer) {
          const cards = els.directoriesCardsContainer.querySelectorAll(".directory-card");
          if (cards.length > 0) {
            const lastCard = cards[cards.length - 1];
            lastCard.scrollIntoView({ behavior: "smooth", block: "nearest" });
          }
        }
        // Сразу открываем проводник для выбора папки у новой карточки:
        // после выбора путь и заголовок из имени папки придут в onDirectorySelected
        callRuby("selectDirectory", newIndex.toString());
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

    // Page orientation / size change updates layout canvas sheet and aspect overlay
    if (els.selectPageLayout) {
      els.selectPageLayout.addEventListener("change", () => {
        renderLayoutCanvas(true);
        renderScenesTable();
        updateAspectUI(true);
      });
    }
    if (els.selectPageSize) {
      els.selectPageSize.addEventListener("change", () => {
        renderLayoutCanvas(true);
        updateAspectUI(true);
      });
    }

    if (els.selectImageAspect) {
      els.selectImageAspect.addEventListener("change", () => updateAspectUI(true));
    }
    if (els.inputAspectCustomW) {
      els.inputAspectCustomW.addEventListener("input", () => updateAspectUI(true));
    }
    if (els.inputAspectCustomH) {
      els.inputAspectCustomH.addEventListener("input", () => updateAspectUI(true));
    }
    if (els.selectQuality) {
      els.selectQuality.addEventListener("change", () => updateAspectUI(true));
    }
    if (els.selectScaleMultiplier) {
      els.selectScaleMultiplier.addEventListener("change", () => updateAspectUI(true));
    }
    if (els.selectAnnotationFontSize) {
      els.selectAnnotationFontSize.addEventListener("change", () => notifyChange());
    }
    if (els.selectLayoutRenderMode) {
      els.selectLayoutRenderMode.addEventListener("change", () => updateAspectUI(true));
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

    const handleFontFamilyChange = (val) => {
      let family = (val || "Sofia Sans Condensed").trim();
      if (family.toLowerCase().includes("din")) {
        family = "Oswald";
      }
      if (els.selectFontFamily && els.selectFontFamily.value !== family) els.selectFontFamily.value = family;
      if (els.selectLayoutFontFamily && els.selectLayoutFontFamily.value !== family) els.selectLayoutFontFamily.value = family;
      if (state.pdf_settings) {
        state.pdf_settings.font_family = family;
      }
      const width = state.pdf_settings?.font_width === "extra_condensed" ? "extra_condensed" : "condensed";
      document.documentElement.style.setProperty("--page-font-family", `"${previewFontFamilyFor(family, width)}", sans-serif`);
      notifyChange();
    };

    const handleFontWeightChange = (val) => {
      const weight = String(val || "normal").toLowerCase() === "bold" ? "bold" : "normal";
      if (state.pdf_settings) {
        state.pdf_settings.font_weight = weight;
      }
      document.documentElement.style.setProperty("--page-font-weight", weight === "bold" ? "700" : "400");
      notifyChange();
    };

    const handleFontWidthChange = (val) => {
      const width = val === "extra_condensed" ? "extra_condensed" : "condensed";
      if (state.pdf_settings) {
        state.pdf_settings.font_width = width;
      }
      const family = (els.selectFontFamily && els.selectFontFamily.value) || (state.pdf_settings?.font_family) || "Sofia Sans Condensed";
      document.documentElement.style.setProperty("--page-font-family", `"${previewFontFamilyFor(family, width)}", sans-serif`);
      notifyChange();
    };

    if (els.selectFontFamily) {
      els.selectFontFamily.addEventListener("change", (e) => handleFontFamilyChange(e.target.value));
    }
    if (els.selectLayoutFontFamily) {
      els.selectLayoutFontFamily.addEventListener("change", (e) => handleFontFamilyChange(e.target.value));
    }
    if (els.selectFontWeight) {
      els.selectFontWeight.addEventListener("change", (e) => handleFontWeightChange(e.target.value));
    }
    if (els.selectFontWidth) {
      els.selectFontWidth.addEventListener("change", (e) => handleFontWidthChange(e.target.value));
    }

    // Stamp select change
    if (els.selectStamp) {
      els.selectStamp.addEventListener("change", (e) => {
        if (els.customStampGroup) els.customStampGroup.style.display = e.target.value === "custom" ? "flex" : "none";
      });
    }

    // Color pickers hex display
    if (els.inputPrimaryColor) {
      els.inputPrimaryColor.addEventListener("input", (e) => {
        if (els.primaryColorHex) els.primaryColorHex.textContent = e.target.value;
      });
    }
    if (els.inputStampColor) {
      els.inputStampColor.addEventListener("input", (e) => {
        if (els.stampColorHex) els.stampColorHex.textContent = e.target.value;
      });
    }

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

    // Глобальный фон: включается/выключается сразу на всех страницах,
    // эскизы в таблице перегенерируются с учётом нового состояния
    if (els.chkScenesBackground) {
      els.chkScenesBackground.addEventListener("change", (e) => {
        const bgOn = e.target.checked;
        (state.scenes || []).forEach((s) => { s.viewport_background = bgOn; });
        updateBlockSlot("image_4_3", { show_background: bgOn });
        requestSceneThumbnails(true);
        notifyChange();
      });
    }

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
        pdf_link: "",
        ver: "",
        rev: ""
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

    // Start Export: без артикула сначала модалка его создания, затем промпт ревизии
    els.btnStartExport.addEventListener("click", () => {
      if (!articulValue()) {
        openArticulPrompt("export");
        return;
      }
      beginExportFlow();
    });

    // Промпт ревизии перед экспортом (вызывается после проверки артикула)
    function beginExportFlow() {
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
    }

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
        const currVerNum = parseInt(els.inputVersion ? els.inputVersion.value : 1, 10) || 1;
        const currVerStr = String(currVerNum).padStart(2, '0');

        // Добавляем новую запись в историю проекта (ревизия — отдельным полем, не в тексте)
        state.history.unshift({
          data: exactTime,
          date: exactTime,
          edit: note,
          text: note,
          description: note,
          pdf_link: "",
          ver: currVerStr,
          rev: nextRevStr
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

    // --- Обязательный артикул: модалка перед сохранением/экспортом ---
    // Без артикула проект не сохраняется: нет папки проекта (<Артикул>/project.yaml)
    let articulPromptAction = null; // "save" | "export"

    function openArticulPrompt(action) {
      articulPromptAction = action;
      if (els.inputArticulPrompt) {
        els.inputArticulPrompt.value = generateArticulLocal(getTradeValue() === "1");
      }
      if (els.articulPromptModal) {
        els.articulPromptModal.classList.remove("hidden");
        setTimeout(() => {
          if (els.inputArticulPrompt) els.inputArticulPrompt.focus();
        }, 50);
      } else {
        // Модалки нет в разметке — сохранение/экспорт без артикула не выполняем
        showNotification("Укажите артикул проекта — без него данные не сохраняются.", "error");
        articulPromptAction = null;
      }
    }

    // Переносит артикул из модалки в форму; false — значение пустое
    function applyArticulFromPrompt() {
      const val = (els.inputArticulPrompt ? els.inputArticulPrompt.value : "").trim();
      if (!val) {
        showNotification("Введите артикул проекта", "warning");
        if (els.inputArticulPrompt) els.inputArticulPrompt.focus();
        return false;
      }
      if (els.inputArticul) els.inputArticul.value = val;
      // Тип проекта выводим из префикса артикула: CF# — коммерческий, HF# — бытовой
      if (val.startsWith("CF#")) {
        setTradeValue("1");
      } else if (val.startsWith("HF#")) {
        setTradeValue("0");
      }
      updateHeaderTitles();
      updateTradeBadge();
      return true;
    }

    function closeArticulPrompt() {
      if (els.articulPromptModal) els.articulPromptModal.classList.add("hidden");
      articulPromptAction = null;
    }

    if (els.btnConfirmArticulSave) {
      els.btnConfirmArticulSave.addEventListener("click", () => {
        if (!applyArticulFromPrompt()) return;
        const action = articulPromptAction;
        closeArticulPrompt();
        if (action === "export") {
          beginExportFlow();
        } else if (action === "save") {
          executeForcedSave();
        }
      });
    }

    if (els.btnCancelArticulPrompt) {
      els.btnCancelArticulPrompt.addEventListener("click", closeArticulPrompt);
    }

    if (els.inputArticulPrompt) {
      els.inputArticulPrompt.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          if (els.btnConfirmArticulSave) els.btnConfirmArticulSave.click();
        } else if (e.key === "Escape") {
          closeArticulPrompt();
        }
      });
    }

    // Forced save: project.yaml в папке артикула + program settings/layout YAML
    function executeForcedSave() {
      const data = collectFormData();
      callRuby("saveProjectYaml", JSON.stringify(data));
    }

    if (els.btnSaveYaml) {
      els.btnSaveYaml.addEventListener("click", () => {
        if (!articulValue()) {
          openArticulPrompt("save");
          return;
        }
        executeForcedSave();
      });
    }

    // Предложение создать артикул: выбор типа проекта (коммерческий/бытовой)
    if (els.btnArticulTypeCommercial) {
      els.btnArticulTypeCommercial.addEventListener("click", () => createProjectArticul(true));
    }
    if (els.btnArticulTypeHousehold) {
      els.btnArticulTypeHousehold.addEventListener("click", () => createProjectArticul(false));
    }
    if (els.btnArticulTypeLater) {
      els.btnArticulTypeLater.addEventListener("click", closeArticulTypeModal);
    }

    // Import: load project data from YAML into in-memory session
    els.btnImportYaml.addEventListener("click", () => {
      callRuby("importYaml");
    });

    // Export: save a full YAML copy to a chosen location
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
      "inputCompany", "inputArticul", "inputTags",
      "inputProjectDescription", "inputAddress", "inputPhone", "inputEmail",
      "inputAuthor", "inputPrice", "inputStartDate", "inputEndDate",
      "inputTotalDuration", "inputStatus", "inputRevision", "inputVersion",
      "inputLastEdit", "inputTaskDescription", "inputTaskDimensions", "inputTaskWishes",
      "inputMaterials", "inputAppliances", "inputLighting", "inputNotes",
      "selectLayoutRenderMode", "selectCompression", "selectImageFormat", "chkSaveLayoutFile",
      "selectWebpQuality",
      "selectPageSize", "selectPageLayout", "inputPageMargin", "inputLayoutMargin", "selectFontFamily", "selectLayoutFontFamily", "selectFontWeight", "selectFontWidth",
      "selectImageAspect", "inputAspectCustomW", "inputAspectCustomH",
      "selectQuality", "selectScaleMultiplier", "selectStamp", "inputCustomStamp",
      "inputPrimaryColor", "inputStampColor", "chkAutoOpen", "chkSaveBackup", "chkAntialias"
    ];
    autoSaveInputIds.forEach((id) => {
      const el = (els && els[id]) || document.getElementById(id);
      if (el) {
        el.addEventListener("input", () => notifyChange());
        el.addEventListener("change", () => notifyChange());
      }
    });

    // Flush any pending auto-save on window close or navigation
    window.addEventListener("beforeunload", () => flushAutoSave());
    window.addEventListener("unload", () => flushAutoSave());
  }

  // Public API exposed on window.app for Ruby calls
  window.app = {
    loadData: function (data) {
      if (!data) return;
      Object.assign(state, data);
      ensureCustomLayouts();
      syncDirectoriesSpecifications();
      renderUI();
      // Если диалог уже открыт на вкладке «Страницы проекта», актуализируем
      // список страниц и эскизы (повторное открытие диалога из меню)
      const scenesPane = document.getElementById("tab-scenes");
      if (scenesPane && scenesPane.classList.contains("active")) {
        refreshScenesFromModel();
      }
      // При открытии панели предлагаем создать артикул (если проект еще без артикула)
      setTimeout(maybeOfferArticulCreation, 300);
    },

    showNotification: showNotification,

    // Папка проекта <Артикул> создана рядом с рабочим файлом (ответ Ruby-колбэка createProjectFolder)
    onProjectFolderCreated: function (folderPath, yamlSaved) {
      if (!folderPath) return;
      showNotification(
        yamlSaved
          ? `Папка проекта создана: ${folderPath} (project.yaml записан)`
          : `Папка проекта создана: ${folderPath}`,
        "success"
      );
    },

    onAutoSaved: function (yamlName) {
      const timeStr = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      const label = yamlName ? `Сохранено (${yamlName})` : `Сохранено ${timeStr}`;
      updateAutoSaveIndicator("saved", label);
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
        const autoName = getFolderName(chosenPath);
        if (autoName) {
          state.directories[idx].title = autoName;
        }
        renderDirectories();
        notifyChange();
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

    onExportSuccess: function (pdfPath, newRevision, lastPdfPath) {
      els.progressOverlay.classList.add("hidden");
      // Открыта копия «_last» рядом с .skp — она первична для пользователя
      state.lastExportedPdf = lastPdfPath || pdfPath;
      els.successPdfPath.textContent = state.lastExportedPdf;
      els.successModal.classList.remove("hidden");

      // Привязываем PDF этого экспорта к самой свежей записи истории
      // (зеркало Ruby-штампа stamp_history_pdf_link!)
      if (state.history && state.history[0] && !(state.history[0].pdf_link || "").trim()) {
        state.history[0].pdf_link = pdfPath;
        renderHistoryTable();
        notifyChange();
      }

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
      const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "1:1", "custom"];
      if (!VALID_ASPECT_RATIOS.includes(ratio)) {
        ratio = "4:3";
      }
      const grpRatio = document.getElementById("grp_image_aspect_ratio");
      if (grpRatio) {
        grpRatio.querySelectorAll(".btn-aspect-ratio").forEach((b) => {
          b.classList.toggle("active", b.dataset.ratio === ratio);
        });
      }
      const idx = layoutState.selectedSceneIndex || 0;
      const scene = (state.scenes || [])[idx];
      if (scene) {
        scene.aspect_ratio = ratio;
        updateSceneTableAspectCell(idx, ratio, scene.viewport_visible !== false);
      }
      updateBlockSlot("image_4_3", { aspect_ratio: ratio });
      if (!state.pdf_settings) state.pdf_settings = {};
      state.pdf_settings.show_aspect_overlay = true;
      state.pdf_settings.image_aspect_ratio = ratio;
      if (els.selectImageAspect) els.selectImageAspect.value = ratio;
      if (els.chkShowAspectOverlay) els.chkShowAspectOverlay.checked = true;
      const chkTpl = document.getElementById("chk_tpl_aspect_overlay");
      if (chkTpl) chkTpl.checked = true;
      const tplBadge = document.getElementById("tplAspectOverlayBadge");
      if (tplBadge) tplBadge.classList.remove("disabled-overlay");
      callRuby("toggleAspectOverlay", true);
      syncCurrentTemplateOverlay(ratio, true);
      notifyChange();
    },

    onAutoSaved: function (yamlName) {
      updateAutoSaveIndicator("saved", yamlName ? `Сохранено (${yamlName})` : "Сохранено");
    },

    onSceneThumbnailsLoaded: function (thumbs) {
      sceneThumbnailsInFlight = false;
      if (thumbs && typeof thumbs === "object") {
        Object.assign(sceneThumbnails, thumbs);
        updateSceneTablePreviews();
      }
    },

    onScenesRefreshed: function (scenes) {
      if (Array.isArray(scenes)) {
        state.scenes = scenes;
        if (layoutState.selectedSceneIndex >= scenes.length) {
          layoutState.selectedSceneIndex = Math.max(0, scenes.length - 1);
        }
      }
      renderScenesTable();
      // Список мог измениться — всегда перегенерируем эскизы заново
      requestSceneThumbnails(true);
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
