/* -------------------------------------------------------------------------------
   DN1C Export PDF 2 - Frontend Application Logic
   Provides two-way binding between HTML UI and SketchUp Ruby API,
   plus Interactive WYSIWYG Page Layout Editor (Drag & Drop Block Positioning)

   В процессе миграции на Vue: состояние уведомлений и модалок живёт в
   ../store.js, рендер — в Vue-компонентах. Бизнес-логика пока остаётся здесь.
------------------------------------------------------------------------------- */

import { ui, showToast as uiShowToast, nextDirUid, defaultDirPreview } from "../store.js";

(function () {
  "use strict";

  // App State
  const state = {
    project_info: {},
    pdf_settings: {},
    scenes: [],
    history: [],
    template_sets: [],
    lastExportedPdf: ""
  };

  // Блок видового экрана по умолчанию (единый для всех шаблонов; отличия —
  // пропорция кадра и масштаб, задаются в DEFAULT_LAYOUTS)
  const DEFAULT_IMAGE_SLOT = {
    x: 25.0, y: 12.0, w: 50.0, h: 82.0,
    visible: true,
    content: "render_viewport",
    show_background: false,
    aspect_ratio: "4:3",
    scale_pct: 100
  };

  // Иконка крестика закрытия/удаления (шрифт Modus Icons, набор connect)
  const MODUS_CROSS_SVG = '<i class="modus-icons icon-close-cross" style="font-size: 11px;">content_close</i>';

  // Ключ шаблона по умолчанию: первый доступный шаблон; legacy-ключ cover —
  // последний фолбэк (готовые шаблоны удаляемы, «cover» может не существовать)
  function defaultTemplateKey() {
    const keys = Object.keys(state.pdf_settings?.custom_layouts || {});
    return keys[0] || "cover";
  }

  // Дата в превью — в печатном формате PDF (dd.mm.yyyy), а не в локали браузера (9/22/2026)
  const previewDate = (d) => {
    const s = String(d || "").trim();
    if (s) return s;
    const now = new Date();
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(now.getDate())}.${pad(now.getMonth() + 1)}.${now.getFullYear()}`;
  };

  // Стадии приходят из Ruby массивом объектов {name, status};
  // поддерживаем и легаси-кортежи [_, done, title]
  const stadiaName = (st) => (st && typeof st === "object" && !Array.isArray(st) && st.name !== undefined)
    ? String(st.name)
    : (Array.isArray(st) ? String(st[2]) : String(st));
  const stadiaMark = (st) => {
    const done = Array.isArray(st) ? !!st[1] : !!(st && st.status);
    return `${done ? "[✓]" : "[ ]"} ${stadiaName(st)}`;
  };

  // -----------------------------------------------------------------------------
  // Источники параметров шаблона. Готовых списков параметров больше нет:
  // пользователь создает параметр сам — выбирает источник данных (поля вкладок
  // «Данные проекта» и «Папки спецификации», плюс сценические и страничные
  // источники) и настраивает размещение на странице. Значения «сырые»:
  // заголовок-префикс задается настройкой самого параметра (label).
  // -----------------------------------------------------------------------------
  const tval = (v) => String(v === undefined || v === null ? "" : v).trim();

  // Запись истории правок: [дата, текст] | {data|date, edit|text} | строка
  const histEntryText = (e) => {
    if (Array.isArray(e)) return `${tval(e[0])} ${tval(e[1])}`.trim();
    if (e && typeof e === "object") {
      const d = tval(e.data || e.date);
      const txt = tval(e.edit || e.text || e.description);
      return `${d} ${txt}`.trim();
    }
    return tval(e);
  };

  const catalogScene = () => {
    const scenes = state.scenes || [];
    if (layoutState.selectedSceneIndex !== undefined && scenes[layoutState.selectedSceneIndex]) {
      return scenes[layoutState.selectedSceneIndex];
    }
    return scenes.find((s) => s.page_type === (layoutState.currentTemplate || defaultTemplateKey())) || scenes[0] || null;
  };

  // Группы источников для диалога создания/редактирования параметра
  function buildParamSources() {
    const groups = [
      { title: "Данные проекта — Паспорт объекта", options: [
        { value: "project.articul",        label: "🔖 Артикул проекта" },
        { value: "project.furniture_name", label: "🪑 Изделие" },
        { value: "project.room_name",      label: "🚪 Помещение / Место установки" },
        { value: "project.address",        label: "📍 Адрес установки" },
        { value: "project.description",    label: "📋 Описание проекта" }
      ] },
      { title: "Данные проекта — Заказчик", options: [
        { value: "customer.id",    label: "🆔 ID заказчика" },
        { value: "customer.name",  label: "👤 Заказчик (контактное лицо)" },
        { value: "project.company", label: "🏢 Название компании" },
        { value: "customer.name_or_company", label: "🔄 Заказчик / Компания (по типу проекта)" },
        { value: "customer.phone", label: "📞 Телефон" },
        { value: "customer.email", label: "✉️ Email" }
      ] },
      { title: "Данные проекта — Ход работы", options: [
        { value: "workflow.author",     label: "👷 Автор / Конструктор" },
        { value: "workflow.price",      label: "💰 Стоимость проекта" },
        { value: "workflow.start_date", label: "📅 Дата начала" },
        { value: "workflow.end_date",   label: "📅 Дата сдачи" },
        { value: "workflow.duration",   label: "⏱️ Длительность / Трудозатраты" },
        { value: "workflow.rate",       label: "🧮 Ставка руб./час" },
        { value: "workflow.version",    label: "🔢 Версия" },
        { value: "workflow.revision",   label: "🏷️ Ревизия" },
        { value: "workflow.date",       label: "🗓️ Дата" },
        { value: "workflow.status",     label: "⏳ Статус" },
        { value: "workflow.stadia",     label: "✅ Стадии проекта (чек-лист)" },
        { value: "workflow.last_edit",  label: "📝 Последние изменения" },
        { value: "workflow.history",    label: "📜 История правок" }
      ] },
      { title: "Сцена", options: [
        { value: "scene.name",        label: "📐 Название сцены" },
        { value: "scene.description", label: "📝 Описание сцены" }
      ] },
      { title: "Страница", options: [
        { value: "page.number_total", label: "📄 Страница | Страниц" },
        { value: "page.toc",          label: "📑 Содержание (список страниц)" }
      ] }
    ];

    // Динамические источники по папкам спецификаций: один параметр на папку,
    // значение — заголовок на своей строке, описание на следующей (dir.N.line)
    const dirs = Array.isArray(state.directories) ? state.directories : [];
    const dirOptions = [];
    dirs.forEach((d, idx) => {
      if (!d) return;
      const t = tval(d.title) || getFolderName(d.path) || `Раздел #${idx + 1}`;
      dirOptions.push({ value: `dir.${idx}.line`, label: `📁 ${t}` });
    });
    if (dirOptions.length > 0) {
      groups.splice(3, 0, { title: "Папки спецификации", options: dirOptions });
    }
    return groups;
  }

  // Человекочитаемое название источника (для списка созданных параметров)
  function paramSourceLabel(source) {
    const s = tval(source);
    const m = s.match(/^dir\.(\d+)\.(title|description|line)$/);
    if (m) {
      const idx = parseInt(m[1], 10);
      const d = (state.directories || [])[idx];
      const t = (d && (tval(d.title) || getFolderName(d.path))) || `Раздел #${idx + 1}`;
      if (m[2] === "line") return `📁 ${t}`;
      return m[2] === "title" ? `📁 ${t} — название` : `📁 ${t} — спецификация`;
    }
    for (const g of buildParamSources()) {
      const opt = g.options.find((o) => o.value === s);
      if (opt) return opt.label;
    }
    return s || "—";
  }

  // Авто-подпись параметра на листе: короткие печатные формулировки для
  // чекбокса «Заголовок», когда текст подписи (label) не задан вручную.
  // Зеркало AUTO_PARAM_LABELS в service/layout_builder.rb — держать синхронно.
  const AUTO_PARAM_LABELS = {
    "project.articul":      "Артикул",
    "project.furniture_name": "Изделие",
    "project.room_name":    "Помещение",
    "project.address":      "Адрес",
    "project.company":      "Компания",
    "project.description":  "Описание проекта",
    "customer.id":          "ID заказчика",
    "customer.name":        "Заказчик",
    "customer.phone":       "Телефон",
    "customer.email":       "Email",
    "workflow.author":      "Автор",
    "workflow.price":       "Стоимость",
    "workflow.start_date":  "Дата начала",
    "workflow.end_date":    "Дата сдачи",
    "workflow.duration":    "Длительность",
    "workflow.rate":        "Ставка руб./час",
    "workflow.version":     "Версия",
    "workflow.revision":    "Ревизия",
    "workflow.date":        "Дата",
    "workflow.status":      "Статус",
    "workflow.stadia":      "Стадии проекта",
    "workflow.last_edit":   "Последние изменения",
    "workflow.history":     "История правок",
    "scene.name":           "Сцена",
    "scene.description":    "Описание",
    "page.number_total":    "Страница",
    "page.toc":             "Содержание"
  };

  // Эффективная подпись параметра: заданный label, иначе авто-подпись из
  // источника; для папок спецификаций — название раздела (dir.N.line без
  // подписи — заголовок уже внутри значения). Пусто — заголовок не печатается
  // даже при включённом «Заголовок».
  function effectiveParamLabel(source, label) {
    const l = tval(label).replace(/:+\s*$/, "").trim();
    if (l) return l;
    const s = tval(source);
    // Условный источник «Заказчик / Компания»: подпись тоже условная —
    // коммерческий проект печатает «Компания», бытовой — «Заказчик»
    if (s === "customer.name_or_company") {
      return getTradeValue() === "1" ? "Компания" : "Заказчик";
    }
    if (AUTO_PARAM_LABELS[s]) return AUTO_PARAM_LABELS[s];
    const m = s.match(/^dir\.(\d+)\.(title|description|line)$/);
    if (m) {
      if (m[2] === "line") return "";
      const idx = parseInt(m[1], 10);
      const d = (state.directories || [])[idx];
      const base = (d && (tval(d.title) || getFolderName(d.path))) || `Раздел #${idx + 1}`;
      return m[2] === "title" ? `${base} — название` : `${base} — спецификация`;
    }
    return "";
  }

  // Живое значение источника для превью (зеркало InfoLineResolver#resolve_param).
  // Пустая строка — данных нет: параметр не выводится на лист.
  function paramPreviewValue(source) {
    const info = state.project_info || {};
    const wf = state.workflow || {};
    const s = tval(source);
    switch (s) {
      case "project.articul":        return tval(info.articul);
      case "project.furniture_name": return tval(info.furniture_name || info.name_product || info.name_project);
      case "project.room_name":      return tval(info.room_name || info.name_place);
      case "project.address":        return tval(info.address || info.adress);
      case "project.company":        return tval(info.company || info.name_company);
      case "project.description":    return tval(info.project_description || info.description);
      case "customer.id":            return tval(info.customer_id || info.id);
      case "customer.name":          return tval(info.name_customer || info.customer);
      case "customer.name_or_company":
        // Условный источник: коммерческий проект — компания, бытовой — заказчик
        return getTradeValue() === "1"
          ? tval(info.company || info.name_company)
          : tval(info.name_customer || info.customer);
      case "customer.phone":         return tval(info.phone);
      case "customer.email":         return tval(info.email);
      case "workflow.author":        return tval(wf.author || info.author);
      case "workflow.price": {
        const v = tval(info.price);
        return v ? `${v} руб.` : "";
      }
      case "workflow.start_date":    return tval(info.start_date);
      case "workflow.end_date":      return tval(info.end_date);
      case "workflow.duration": {
        const d = tval(info.total_duration);
        return d ? (/дн|день|час/i.test(d) ? d : `${d} дн.`) : "";
      }
      case "workflow.rate":          return tval(wf.rate || info.rate);
      case "workflow.version":       return `v${tval(wf.version || info.version) || "01"}`;
      case "workflow.revision":      return `#r${tval(wf.revision || info.revision) || "001"}`;
      case "workflow.date":          return previewDate(wf.date_order || info.date);
      case "workflow.status":        return tval(wf.status || info.status);
      case "workflow.stadia": {
        const arr = (Array.isArray(wf.stadia) && wf.stadia.length > 0) ? wf.stadia
                  : ((Array.isArray(info.stadia) && info.stadia.length > 0) ? info.stadia : null);
        return arr ? arr.map(stadiaMark).join("\n") : tval(wf.status || info.status);
      }
      case "workflow.last_edit": {
        const h = wf.history_edit || info.history_edit;
        if (Array.isArray(h) && h.length > 0) return histEntryText(h[0]);
        return tval(wf.last_edit || info.last_edit);
      }
      case "workflow.history": {
        const h = wf.history_edit || info.history_edit;
        return Array.isArray(h) ? h.map(histEntryText).filter(Boolean).join("\n") : tval(wf.last_edit || info.last_edit);
      }
      case "scene.name": {
        const sc = catalogScene();
        return tval(sc && (sc.name || sc.original_name));
      }
      case "scene.description": {
        const sc = catalogScene();
        return tval(sc && sc.description);
      }
      case "page.number_total":
        // Нумерация известна только при экспорте — в превью условный образец
        return "Страница 1 | N";
      case "page.toc": {
        const sc = (state.scenes || []).filter((x) => x.enabled !== false);
        return sc.length > 0 ? sc.map((x, i) => `${i + 1}. ${x.name}`).join("\n") : "";
      }
      default: {
        const m = s.match(/^dir\.(\d+)\.(title|description|line)$/);
        if (m) {
          const d = (state.directories || [])[parseInt(m[1], 10)];
          if (!d) return "";
          if (m[2] === "line") {
            return [tval(d.title), tval(d.description)].filter(Boolean).join("\n");
          }
          return tval(d[m[2] === "title" ? "title" : "description"]);
        }
        return "";
      }
    }
  }

  // Одинаковые для всех параметров настройки по умолчанию.
  // Место на странице определяется выравниваниями: лево/центр/право — колонка,
  // верх/низ — привязка группы к верхнему или нижнему краю листа.
  const DEFAULT_PARAM_SETTINGS = {
    align: "left",
    valign: "top",
    font_family: "",
    font_size: 10,
    color: "#0F172A"
  };

  const PARAM_FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72];

  // Варианты «размера между строками» (мм) — общий отступ между параметрами
  // и блоками на листе; задается один раз в шапке карточки «Параметры страницы»
  const PARAM_LINE_GAPS = [0, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];

  // Шрифты комплекта плагина для построчного выбора («По умолчанию» = шрифт страницы)
  const PARAM_FONT_FAMILIES = [
    { value: "", label: "По умолчанию" },
    { value: "Sofia Sans Condensed", label: "Sofia Sans Condensed" },
    { value: "Sofia Sans Extra Condensed", label: "Sofia Sans Extra Condensed" },
    { value: "Oswald", label: "Oswald" },
    { value: "Roboto Condensed", label: "Roboto Condensed" },
    { value: "Ubuntu Condensed", label: "Ubuntu Condensed" }
  ];

  // Нормализация параметра шаблона (зеркало ProjectData#normalize_template_params).
  // Запись с group: true — блок объединения параметров: вложенные параметры
  // выводятся одной строкой с разделителем « | ».
  function normalizeTemplateParam(raw) {
    const p = raw && typeof raw === "object" ? raw : {};
    const bool = (v, def) => (v === undefined || v === null) ? def : !(v === false || v === "false" || v === 0 || v === "0");
    const num = (v, def, min, max) => {
      const n = parseFloat(v);
      return isNaN(n) ? def : Math.min(max, Math.max(min, n));
    };
    const alignRaw = tval(p.align);
    const valignRaw = tval(p.valign);
    const ffRaw = tval(p.font_family);
    const common = {
      id: tval(p.id),
      // Двоеточие после метки добавляет рендерер — хвостовые «:» из ввода срезаем
      label: tval(p.label).replace(/:+\s*$/, "").trim(),
      show_label: bool(p.show_label, true),
      align: ["left", "center", "right"].includes(alignRaw) ? alignRaw : "left",
      valign: ["top", "bottom"].includes(valignRaw) ? valignRaw : "top",
      font_family: PARAM_FONT_FAMILIES.some((f) => f.value === ffRaw) ? ffRaw : "",
      font_size: num(p.font_size, DEFAULT_PARAM_SETTINGS.font_size, 4, 72),
      color: /^#[0-9a-fA-F]{6}$/.test(tval(p.color)) ? tval(p.color) : DEFAULT_PARAM_SETTINGS.color,
      visible: bool(p.visible, true)
    };

    if (p.group === true || p.group === "true") {
      const children = Array.isArray(p.params) ? p.params : [];
      return Object.assign(common, {
        id: common.id || `g_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
        group: true,
        show_label: bool(p.show_label, false),
        params: children
          .filter((c) => c && typeof c === "object" && tval(c.source))
          .map((c) => ({
            id: tval(c.id) || `c_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
            source: tval(c.source),
            label: tval(c.label),
            show_label: bool(c.show_label, false)
          }))
      });
    }

    return Object.assign(common, {
      id: common.id || `p_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`,
      source: tval(p.source)
    });
  }

  // Создание пустого блока объединения параметров
  function createParamGroup(tplKey) {
    ensureCustomLayouts();
    const key = tplKey || layoutState.currentTemplate || defaultTemplateKey();
    if (!state.pdf_settings.custom_layouts[key]) {
      state.pdf_settings.custom_layouts[key] = {};
    }
    const group = normalizeTemplateParam({
      group: true,
      label: "",
      show_label: false,
      align: DEFAULT_PARAM_SETTINGS.align,
      valign: DEFAULT_PARAM_SETTINGS.valign,
      font_family: DEFAULT_PARAM_SETTINGS.font_family,
      font_size: DEFAULT_PARAM_SETTINGS.font_size,
      color: DEFAULT_PARAM_SETTINGS.color,
      visible: true,
      params: []
    });
    state.pdf_settings.custom_layouts[key].params.push(group);
    renderTemplateSettingsList();
    notifyChange();
    showNotification("Блок создан — перетащите в него параметры", "success");
  }

  // Название зоны размещения параметра (для сводки в строке)
  function paramZoneLabel(p) {
    const h = p.align === "center" ? "По центру" : (p.align === "right" ? "Справа" : "Слева");
    const v = p.valign === "bottom" ? "внизу" : "вверху";
    return `${h} ${v}`;
  }

  // «N параметров» с согласованием окончаний
  function paramCountText(n) {
    const mod10 = n % 10;
    const mod100 = n % 100;
    const word = (mod10 === 1 && mod100 !== 11) ? "параметр"
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) ? "параметра"
        : "параметров";
    return `${n} ${word}`;
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

// Структурный фолбэк для известных ключей шаблонов (имя + видовой экран):
// используется только как источник значений по умолчанию — готовые шаблоны
// живут в state.pdf_settings.custom_layouts и создаются/удаляются как обычные.
const DEFAULT_LAYOUTS = {
  cover: {
    name: "Титульный лист (Cover)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { scale_pct: 80 })
  },
  description: {
    name: "Описание и спецификации (Description)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { scale_pct: 70 })
  },
  explain: {
    name: "Содержание и ведомость (Explain)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { scale_pct: 60 })
  },
  general: {
    name: "Общий вид (General)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { aspect_ratio: "16:9" })
  },
  visual: {
    name: "Визуализация (Visual)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { aspect_ratio: "16:9" })
  },
  blank: {
    name: "Без шаблона (Blank)",
    image_4_3: Object.assign({}, DEFAULT_IMAGE_SLOT, { aspect_ratio: "16:9" })
  }
};


  // Layout Editor Internal State
  const layoutState = {
    currentTemplate: "cover",
    selectedSceneIndex: 0
  };

  // DOM Elements Cache
  const els = {
    tabs: document.querySelectorAll(".tab-btn"),
    tabPanes: document.querySelectorAll(".tab-pane"),
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
    inputRate: document.getElementById("inputRate"),
    inputStatus: document.getElementById("inputStatus"),
    stadiaCheckboxesContainer: document.getElementById("stadiaCheckboxesContainer"),
    inputNewStadia: document.getElementById("inputNewStadia"),
    btnAddStadia: document.getElementById("btnAddStadia"),
    inputLastEdit: document.getElementById("inputLastEdit"),

    // Tab Directories
    // Вкладка «Папки» рендерится Vue-компонентом DirectoriesTab.vue

    // Tab Settings
    apiTargetsList: document.getElementById("apiTargetsList"),
    btnAddApiTarget: document.getElementById("btnAddApiTarget"),

    // Tab 2 Elements: Scenes & Layout Split View
    layoutTplUsageBadge: document.getElementById("layoutTplUsageBadge"),
    scenesTableBody: document.getElementById("scenesTableBody"),
    btnSelectAllScenes: document.getElementById("btnSelectAllScenes"),
    btnDeselectAllScenes: document.getElementById("btnDeselectAllScenes"),
    btnApplyTemplateAll: document.getElementById("btnApplyTemplateAll"),
    btnRefreshThumbs: document.getElementById("btnRefreshThumbs"),
    chkScenesBackground: document.getElementById("chk_scenes_background"),
    chkScenesWatermarks: document.getElementById("chk_scenes_watermarks"),
    chkScenesFrameAll: document.getElementById("chk_scenes_frame_all"),
    scenesPanel: document.getElementById("scenesPanel"),
    scenesSplitResizer: document.getElementById("scenesSplitResizer"),

    // Template & List Settings Elements
    templatesSidebar: document.getElementById("templatesSidebar"),
    templatesList: document.getElementById("templatesList"),
    btnCreateTemplate: document.getElementById("btnCreateTemplate"),
    currentTemplateTitle: document.getElementById("currentTemplateTitle"),
    btnRenameCurrentTemplate: document.getElementById("btnRenameCurrentTemplate"),
    btnDeleteCurrentTemplate: document.getElementById("btnDeleteCurrentTemplate"),
    newTemplateModal: document.getElementById("newTemplateModal"),
    inputNewTemplateName: document.getElementById("inputNewTemplateName"),
    inputNewTemplateDescription: document.getElementById("inputNewTemplateDescription"),
    selectNewTemplateBase: document.getElementById("selectNewTemplateBase"),
    btnConfirmNewTemplate: document.getElementById("btnConfirmNewTemplate"),
    btnCancelNewTemplate: document.getElementById("btnCancelNewTemplate"),
    deleteTemplateModal: document.getElementById("deleteTemplateModal"),
    deleteTemplateMsg: document.getElementById("deleteTemplateMsg"),
    btnCancelDeleteTemplate: document.getElementById("btnCancelDeleteTemplate"),
    btnConfirmDeleteTemplate: document.getElementById("btnConfirmDeleteTemplate"),
    renameTemplateModal: document.getElementById("renameTemplateModal"),
    inputRenameTemplateName: document.getElementById("inputRenameTemplateName"),
    inputRenameTemplateDescription: document.getElementById("inputRenameTemplateDescription"),
    btnCancelRenameTemplate: document.getElementById("btnCancelRenameTemplate"),
    btnConfirmRenameTemplate: document.getElementById("btnConfirmRenameTemplate"),
    templateSetsList: document.getElementById("templateSetsList"),
    btnSaveTemplateSet: document.getElementById("btnSaveTemplateSet"),
    saveTemplateSetModal: document.getElementById("saveTemplateSetModal"),
    inputTemplateSetName: document.getElementById("inputTemplateSetName"),
    btnCancelSaveTemplateSet: document.getElementById("btnCancelSaveTemplateSet"),
    btnConfirmSaveTemplateSet: document.getElementById("btnConfirmSaveTemplateSet"),
    confirmTemplateSetModal: document.getElementById("confirmTemplateSetModal"),
    confirmTemplateSetTitle: document.getElementById("confirmTemplateSetTitle"),
    confirmTemplateSetMsg: document.getElementById("confirmTemplateSetMsg"),
    confirmTemplateSetWarning: document.getElementById("confirmTemplateSetWarning"),
    btnCancelConfirmTemplateSet: document.getElementById("btnCancelConfirmTemplateSet"),
    btnConfirmTemplateSet: document.getElementById("btnConfirmTemplateSet"),
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
    chkAutoOpen: document.getElementById("chkAutoOpen"),
    chkSaveBackup: document.getElementById("chkSaveBackup"),
    chkAntialias: document.getElementById("chkAntialias"),

    // Tab 4 Elements
    // История рендерится Vue-компонентом HistoryTab.vue

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
      if (action === "getData") {
        setTimeout(() => {
          if (window.app && window.app.loadData) {
            const scenesList = [
              { name: "Титульный лист", page_type: "cover", description: "Обложка проекта", enabled: true, aspect_ratio: "4:3", scale_pct: 100, viewport_visible: true, align_h: "center", align_v: "center" },
              { name: "Содержание и материалы", page_type: "explain", description: "Пояснительная записка и перечень спецификаций", enabled: true, aspect_ratio: "4:3", scale_pct: 90, viewport_visible: true, align_h: "center", align_v: "center" },
              { name: "Перспективный вид", page_type: "visual", description: "Визуализация интерьера в дневном освещении", enabled: true, aspect_ratio: "16:9", scale_pct: 100, viewport_visible: true, align_h: "center", align_v: "center" },
              { name: "План расстановки мебели", page_type: "general", description: "Техническая схема с габаритными размерами", enabled: true, aspect_ratio: "4:3", scale_pct: 80, viewport_visible: true, align_h: "center", align_v: "center" }
            ];
            window.app.loadData({
              project: {
                articul: "HF#260924_104500",
                articul_locked: true,
                furniture_name: "Шкаф купе, Тумба прикроватная, Зеркало",
                place: "Прихожая и Спальня",
                adress: "г. Москва, ул. Арбат, д. 24, кв. 12",
                description: "Комплексный дизайн-проект интерьера с технической документацией",
                commercial: false
              },
              customer: {
                id: "CUST-2609241045",
                name: "Алексей Смирнов",
                phone: "+7 (999) 123-45-67",
                email: "alex@example.com"
              },
              workflow: {
                author: "Иванов И.И.",
                price: "245 000",
                start_date: "2026-09-01",
                end_date: "2026-09-30",
                total_duration: "14 дней / 65 часов",
                version: "02",
                revision: "003",
                last_edit: "Добавлены замки и скорректированы габариты тумбы",
                stadia: [
                  { name: "Предварительный проект", status: true },
                  { name: "Правки проекта (история правок)", status: true },
                  { name: "Выбраны материалы и фурнитура", status: true },
                  { name: "Предварительно Утвержден", status: true },
                  { name: "Проверка технологом", status: false },
                  { name: "Утвержден в производство", status: false }
                ]
              },
              project_info: {
                articul: "HF#260924_104500",
                articul_locked: true,
                furniture_name: "Шкаф купе, Тумба прикроватная, Зеркало",
                room_name: "Прихожая и Спальня",
                address: "г. Москва, ул. Арбат, д. 24, кв. 12",
                company: "ООО \"Интерьер-Дизайн\"",
                project_description: "Комплексный дизайн-проект интерьера с технической документацией",
                customer_id: "CUST-2609241045",
                name_customer: "Алексей Смирнов",
                phone: "+7 (999) 123-45-67",
                email: "alex@example.com",
                author: "Иванов И.И.",
                price: "245 000",
                start_date: "2026-09-01",
                end_date: "2026-09-30",
                total_duration: "14 дней / 65 часов",
                version: "02",
                revision: "003",
                last_edit: "Добавлены замки и скорректированы габариты тумбы",
                stadia: [
                  { name: "Предварительный проект", status: true },
                  { name: "Правки проекта (история правок)", status: true },
                  { name: "Выбраны материалы и фурнитура", status: true },
                  { name: "Предварительно Утвержден", status: true },
                  { name: "Проверка технологом", status: false },
                  { name: "Утвержден в производство", status: false }
                ]
              },
              scenes: scenesList,
              pdf_settings: {
                page_size: "A3",
                page_layout: "landscape",
                margin_mm: 5,
                show_aspect_overlay: true,
                image_aspect_ratio: "4:3",
                font_family: "Sofia Sans Condensed",
                font_weight: "normal",
                font_width: "condensed",
                layout_render_mode: "image",
                image_format: "png",
                quality: "medium",
                scale_multiplier: "2.0",
                save_layout_file: true,
                save_backup: true,
                antialias: true
              },
              directories: [
                { path: "U:/dn1code/projects/specifications", title: "Рабочие спецификации", description: "Чертежи раскроя, список кромки и фурнитуры Blum" },
                { path: "U:/dn1code/projects/photos", title: "Фотографии объекта", description: "Замеры стен, розеток и вентиляции" }
              ],
              history: [
                { data: "2026-09-24 10:30", edit: "Корректировка фасадов шкафа (rev. 003)", pdf_link: "project_rev003.pdf" },
                { data: "2026-09-20 15:45", edit: "Первоначальное согласование (rev. 002)", pdf_link: "project_rev002.pdf" },
                { data: "2026-09-15 11:20", edit: "Создание проекта (rev. 001)", pdf_link: "project_rev001.pdf" }
              ],
              vips_available: true
            });
          }
        }, 50);
      }
      if (action === "refreshScenes") {
        setTimeout(() => {
          if (window.app && window.app.onScenesRefreshed) {
            window.app.onScenesRefreshed(state.scenes || []);
          }
        }, 50);
      }
      if (action === "getSceneThumbnails") {
        setTimeout(() => {
          if (window.app && window.app.onSceneThumbnailsLoaded) {
            window.app.onSceneThumbnailsLoaded({});
          }
        }, 50);
      }
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
          } else if (tab.dataset.tab === "tab-send") {
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
    } else if (tabId === "tab-send") {
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

  // Toast Notifications (рендер — в Vue-компоненте AppToast через ui-store)
  function showNotification(msg, type = "success") {
    uiShowToast(msg, type);
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
  // Template Layout Engine: видовое окно + пользовательские параметры
  // -----------------------------------------------------------------------------

  // Нормализация конфигов шаблонов. Чистый лист: блоки старой модели
  // (header/slot_1..4/footer) удаляются; остаются только image_4_3, params,
  // общие настройки стека параметров (line_gap/line_enabled) и метаданные
  // шаблона (name/_name/_description/description/_base_type/_icon).
  // ВАЖНО: ключи из DEFAULT_LAYOUTS здесь не досоздаются — удалённый
  // пользователем шаблон не должен воскресать при следующей отрисовке.
  function ensureCustomLayouts() {
    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};

    const metaKeys = new Set(["name", "_name", "description", "_description", "_base_type", "_icon", "_meta"]);

    const allTplKeys = Object.keys(state.pdf_settings.custom_layouts);

    allTplKeys.forEach((tplKey) => {
      const cfg = state.pdf_settings.custom_layouts[tplKey];
      if (!cfg || typeof cfg !== "object") {
        state.pdf_settings.custom_layouts[tplKey] = {};
        return;
      }

      Object.keys(cfg).forEach((k) => {
        if (k !== "image_4_3" && k !== "params" && k !== "line_gap" && k !== "line_enabled" && !metaKeys.has(k)) {
          delete cfg[k];
        }
      });

      const baseKey = cfg._base_type || (DEFAULT_LAYOUTS[tplKey] ? tplKey : "general");
      const defImg = (DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general).image_4_3 || DEFAULT_IMAGE_SLOT;

      if (!cfg.image_4_3 || typeof cfg.image_4_3 !== "object") {
        cfg.image_4_3 = deepClone(defImg);
      } else {
        cfg.image_4_3.visible = isSlotVisible(cfg.image_4_3);
        if (!cfg.image_4_3.content) cfg.image_4_3.content = defImg.content || "render_viewport";
        if (!cfg.image_4_3.aspect_ratio) cfg.image_4_3.aspect_ratio = defImg.aspect_ratio || "4:3";
        if (cfg.image_4_3.scale_pct === undefined) cfg.image_4_3.scale_pct = defImg.scale_pct !== undefined ? defImg.scale_pct : 100;
        if (cfg.image_4_3.x === undefined) cfg.image_4_3.x = defImg.x;
        if (cfg.image_4_3.y === undefined) cfg.image_4_3.y = defImg.y;
        if (cfg.image_4_3.w === undefined) cfg.image_4_3.w = defImg.w;
        if (cfg.image_4_3.h === undefined) cfg.image_4_3.h = defImg.h;
      }

      if (!Array.isArray(cfg.params)) {
        cfg.params = [];
      } else {
        cfg.params = cfg.params
          .filter((p) => p && typeof p === "object" && (p.group === true || p.group === "true" || tval(p.source)))
          .map(normalizeTemplateParam);
      }

      // Общие настройки стека параметров (шапка карточки) нормализуются здесь,
      // зеркально normalize_line_settings! в project_data.rb — иначе выбранное
      // значение сбрасывалось бы при каждой перерисовке и не попадало в layout.yaml
      const rawGap = parseFloat(cfg.line_gap);
      cfg.line_gap = isNaN(rawGap) ? 2.5 : Math.min(50, Math.max(0, rawGap));
      const rawLine = cfg.line_enabled;
      cfg.line_enabled = rawLine !== undefined && rawLine !== null &&
                         !(rawLine === false || rawLine === "false" || rawLine === 0 || rawLine === "0");
    });
  }

  // -----------------------------------------------------------------------------
  // Dynamic Template Registry & Management
  // -----------------------------------------------------------------------------
  function getAllTemplates() {
    const customLayouts = state.pdf_settings?.custom_layouts || {};

    // Все шаблоны равнозначны (готовые живут в custom_layouts наравне с
    // пользовательскими); имена legacy-записей без меты берём из DEFAULT_LAYOUTS
    return Object.keys(customLayouts).map((key) => {
      const tplObj = customLayouts[key] || {};
      const name = tplObj._name || tplObj.name ||
                   state.pdf_settings?.template_names?.[key] ||
                   (DEFAULT_LAYOUTS[key] && DEFAULT_LAYOUTS[key].name) ||
                   `Шаблон (${key})`;
      const description = tplObj._description || tplObj.description || "";

      return {
        key: key,
        name: name,
        description: description,
        icon: "",
        modusIcon: "",
        isDefault: false,
        baseType: tplObj._base_type || (DEFAULT_LAYOUTS[key] ? key : "general")
      };
    });
  }

  function getTemplateDef(tplKey) {
    const customLayouts = state.pdf_settings?.custom_layouts || {};
    const custom = customLayouts[tplKey] || {};
    const baseKey = custom._base_type || (DEFAULT_LAYOUTS[tplKey] ? tplKey : "general");
    const baseDef = DEFAULT_LAYOUTS[baseKey] || DEFAULT_LAYOUTS.general;
    const name = custom._name || custom.name ||
                 state.pdf_settings?.template_names?.[tplKey] ||
                 (DEFAULT_LAYOUTS[tplKey] && DEFAULT_LAYOUTS[tplKey].name) ||
                 `Шаблон (${tplKey})`;
    const description = custom._description || custom.description || "";

    return {
      key: tplKey,
      name: name,
      description: description,
      icon: "",
      modusIcon: "",
      isDefault: false,
      baseType: baseKey,
      image_def: baseDef.image_4_3 || DEFAULT_IMAGE_SLOT
    };
  }

  function renderTemplatesList() {
    const listEl = els.templatesList || document.getElementById("templatesList");
    if (!listEl) return;
    listEl.innerHTML = "";

    const templates = getAllTemplates();
    const currentKey = layoutState.currentTemplate || (templates[0] ? templates[0].key : "");
    const scenes = state.scenes || [];

    templates.forEach((tpl) => {
      const item = document.createElement("div");
      item.className = `template-list-item${tpl.key === currentKey ? " active" : ""}`;
      item.dataset.tpl = tpl.key;

      const matchingScenes = scenes.filter((s) => s.page_type === tpl.key);
      const usageText = matchingScenes.length > 0
        ? `${matchingScenes.length} ${matchingScenes.length === 1 ? "сцена" : (matchingScenes.length < 5 ? "сцены" : "сцен")}`
        : "не используется";

      // Второй строкой — описание шаблона (мелче); без описания — использование
      const subText = tpl.description || usageText;
      item.title = subText;

      const mainDiv = document.createElement("div");
      mainDiv.className = "tpl-item-main";

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
      mainDiv.appendChild(textDiv);
      item.appendChild(mainDiv);

      // Actions (rename / delete — доступны для любого шаблона)
      const actionsDiv = document.createElement("div");
      actionsDiv.className = "tpl-item-actions";

        const btnRename = document.createElement("button");
        btnRename.type = "button";
        btnRename.className = "tpl-item-action-btn";
        btnRename.title = "Переименовать шаблон";
        btnRename.innerHTML = '<i class="modus-icons" style="font-size: 14px;">edit</i>';
        btnRename.addEventListener("click", (e) => {
          e.stopPropagation();
          promptRenameTemplate(tpl.key);
        });

        const btnDel = document.createElement("button");
        btnDel.type = "button";
        btnDel.className = "tpl-item-action-btn delete";
        btnDel.title = "Удалить шаблон";
        btnDel.innerHTML = '<i class="modus-icons" style="font-size: 14px;">delete</i>';
        btnDel.addEventListener("click", (e) => {
          e.stopPropagation();
          deleteCustomTemplate(tpl.key);
        });

      actionsDiv.appendChild(btnRename);
      actionsDiv.appendChild(btnDel);
      item.appendChild(actionsDiv);

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
    if (!isSlotVisible(imgCfg, true)) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      callRuby("toggleAspectOverlay", false);
    }

    if (els.currentTemplateTitle) {
      els.currentTemplateTitle.textContent = tplDef.name;
    }

    if (els.selectLayoutTemplate) {
      els.selectLayoutTemplate.value = tplKey;
    }

    // Все шаблоны равнозначны: удалить/переименовать можно любой
    if (els.btnDeleteCurrentTemplate) {
      els.btnDeleteCurrentTemplate.style.display = "inline-flex";
    }
    if (els.btnRenameCurrentTemplate) {
      els.btnRenameCurrentTemplate.style.display = "inline-flex";
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
        opt.textContent = t.name;
        if (t.key === currentVal) opt.selected = true;
        els.selectLayoutTemplate.appendChild(opt);
      });
    }
  }

  function createCustomTemplate(name, baseKey = "empty", description = "") {
    if (!name || !name.trim()) return;
    const trimmedName = name.trim();
    const trimmedDesc = (description || "").trim();

    ensureCustomLayouts();
    const newKey = "custom_" + Date.now().toString(36);

    // Копия актуальной конфигурации шаблона-основы (видовое окно + параметры);
    // «Пустой шаблон» стартует с базовым видовым экраном и без параметров
    const baseCfg = state.pdf_settings.custom_layouts[baseKey] ||
      { image_4_3: deepClone(DEFAULT_IMAGE_SLOT), params: [], line_gap: 2.5, line_enabled: false };
    state.pdf_settings.custom_layouts[newKey] = deepClone(baseCfg);
    state.pdf_settings.custom_layouts[newKey].name = trimmedName;
    state.pdf_settings.custom_layouts[newKey]._name = trimmedName;
    if (trimmedDesc) {
      state.pdf_settings.custom_layouts[newKey].description = trimmedDesc;
      state.pdf_settings.custom_layouts[newKey]._description = trimmedDesc;
    }
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
    if (!tplKey) {
      return;
    }
    templatePendingDelete = tplKey;
    const tplDef = getTemplateDef(tplKey);
    if (els.deleteTemplateMsg) {
      els.deleteTemplateMsg.textContent = `Вы действительно хотите удалить шаблон «${tplDef.name}»?`;
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
    if (!tplKey) {
      closeDeleteTemplateModal();
      return;
    }
    const tplDef = getTemplateDef(tplKey);

    if (state.pdf_settings?.custom_layouts) {
      delete state.pdf_settings.custom_layouts[tplKey];
    }
    if (state.pdf_settings?.template_names) {
      delete state.pdf_settings.template_names[tplKey];
    }

    // Сцены удалённого шаблона переключаем на первый оставшийся шаблон;
    // если шаблонов не осталось — ключ страницы оставляем как есть
    const remaining = Object.keys(state.pdf_settings?.custom_layouts || {});
    const fallbackKey = remaining[0] || "";
    let reassignedCount = 0;
    if (fallbackKey) {
      (state.scenes || []).forEach((s) => {
        if (s.page_type === tplKey) {
          s.page_type = fallbackKey;
          reassignedCount++;
        }
      });
    }

    closeDeleteTemplateModal();
    syncTemplateDropdowns();
    renderTemplatesList();
    renderScenesTable();
    if (fallbackKey) {
      layoutState.currentTemplate = fallbackKey;
      selectTemplate(fallbackKey);
    } else {
      layoutState.currentTemplate = "";
      renderTemplateSettingsList(true);
      updateLayoutUsageBadge();
    }
    notifyChange();
    showNotification(`Шаблон «${tplDef.name}» удален${reassignedCount > 0 ? ` (сцен переключено: ${reassignedCount})` : ""}`, "info");
  }

  function deleteCustomTemplate(tplKey) {
    openDeleteTemplateModal(tplKey);
  }

  // -----------------------------------------------------------------------------
  // Template Sets: сохранение/загрузка всего списка шаблонов под разные проекты.
  // Набор — снимок custom_layouts в config/layout_sets/*.yaml; загрузка заменяет
  // все шаблоны, сцены отсутствующих шаблонов уходят на первый доступный.
  // -----------------------------------------------------------------------------
  let templateSetPendingAction = null; // { type: "load" | "overwrite" | "delete", name }

  function templateSetsCountWord(n) {
    if (n === 1) return "шаблон";
    return n > 1 && n < 5 ? "шаблона" : "шаблонов";
  }

  function formatTemplateSetDate(raw) {
    const s = String(raw || "").trim();
    if (!s) return "";
    const d = new Date(s);
    if (isNaN(d.getTime())) return s;
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}`;
  }

  function renderTemplateSetsList() {
    const listEl = els.templateSetsList || document.getElementById("templateSetsList");
    if (!listEl) return;
    listEl.innerHTML = "";

    const sets = state.template_sets || [];
    if (!sets.length) {
      const empty = document.createElement("div");
      empty.className = "template-set-empty";
      empty.textContent = "Нет сохраненных наборов";
      listEl.appendChild(empty);
      return;
    }

    sets.forEach((set) => {
      const item = document.createElement("div");
      item.className = "template-set-item";
      item.title = `Загрузить набор «${set.name}» (текущие шаблоны будут заменены)`;

      const textDiv = document.createElement("div");
      textDiv.className = "tpl-item-text";

      const nameSpan = document.createElement("span");
      nameSpan.className = "tpl-item-name";
      nameSpan.textContent = set.name;

      const subSpan = document.createElement("span");
      subSpan.className = "tpl-item-sub";
      const count = set.templates_count || 0;
      const dateStr = formatTemplateSetDate(set.saved_at);
      subSpan.textContent = `${count} ${templateSetsCountWord(count)}${dateStr ? ` · ${dateStr}` : ""}`;

      textDiv.appendChild(nameSpan);
      textDiv.appendChild(subSpan);
      item.appendChild(textDiv);

      const btnRefresh = document.createElement("button");
      btnRefresh.type = "button";
      btnRefresh.className = "tpl-item-action-btn refresh";
      btnRefresh.title = "Обновить набор: перезаписать его текущим списком шаблонов";
      btnRefresh.innerHTML = '<i class="modus-icons" style="font-size: 14px;">refresh</i>';
      btnRefresh.addEventListener("click", (e) => {
        e.stopPropagation();
        openConfirmTemplateSetModal({ type: "refresh", name: set.name });
      });

      const btnDel = document.createElement("button");
      btnDel.type = "button";
      btnDel.className = "tpl-item-action-btn delete";
      btnDel.title = "Удалить набор";
      btnDel.innerHTML = '<i class="modus-icons" style="font-size: 14px;">delete</i>';
      btnDel.addEventListener("click", (e) => {
        e.stopPropagation();
        openConfirmTemplateSetModal({ type: "delete", name: set.name });
      });

      const actionsDiv = document.createElement("div");
      actionsDiv.className = "tpl-item-actions";
      actionsDiv.appendChild(btnRefresh);
      actionsDiv.appendChild(btnDel);
      item.appendChild(actionsDiv);

      item.addEventListener("click", () => {
        openConfirmTemplateSetModal({ type: "load", name: set.name });
      });

      listEl.appendChild(item);
    });
  }

  function openConfirmTemplateSetModal(action) {
    templateSetPendingAction = action;
    const name = action ? action.name : "";
    const isDelete = !!action && action.type === "delete";
    const isOverwrite = !!action && action.type === "overwrite";
    const isRefresh = !!action && action.type === "refresh";

    if (els.confirmTemplateSetTitle) {
      els.confirmTemplateSetTitle.textContent = isDelete
        ? "Удаление набора шаблонов"
        : (isOverwrite ? "Перезапись набора шаблонов"
            : (isRefresh ? "Обновление набора шаблонов" : "Загрузка набора шаблонов"));
    }
    if (els.confirmTemplateSetMsg) {
      els.confirmTemplateSetMsg.textContent = isDelete
        ? `Вы действительно хотите удалить набор «${name}»?`
        : (isOverwrite
            ? `Набор «${name}» уже существует. Перезаписать его текущим списком шаблонов?`
            : (isRefresh
                ? `Обновить набор «${name}» текущим списком шаблонов? Содержимое набора будет перезаписано.`
                : `Вы действительно хотите загрузить набор «${name}»?`));
    }
    if (els.confirmTemplateSetWarning) {
      els.confirmTemplateSetWarning.style.display = (isDelete || isOverwrite || isRefresh) ? "none" : "";
    }
    if (els.btnConfirmTemplateSet) {
      els.btnConfirmTemplateSet.classList.toggle("btn-danger", isDelete);
      els.btnConfirmTemplateSet.classList.toggle("btn-primary", !isDelete);
      const icon = els.btnConfirmTemplateSet.querySelector(".modus-icons");
      if (icon) icon.textContent = isDelete ? "delete" : "check_mark";
    }
    if (els.confirmTemplateSetModal) {
      els.confirmTemplateSetModal.classList.remove("hidden");
    }
  }

  function closeConfirmTemplateSetModal() {
    templateSetPendingAction = null;
    if (els.confirmTemplateSetModal) {
      els.confirmTemplateSetModal.classList.add("hidden");
    }
  }

  function confirmTemplateSetAction() {
    const action = templateSetPendingAction;
    closeConfirmTemplateSetModal();
    if (!action) return;

    if (action.type === "delete") {
      callRuby("deleteTemplateSet", JSON.stringify(action.name));
    } else if (action.type === "load") {
      flushAutoSave();
      callRuby("loadTemplateSet", JSON.stringify(action.name));
    } else if (action.type === "overwrite" || action.type === "refresh") {
      // Обновление набора — та же перезапись: текущие шаблоны сохраняются
      // под именем существующего набора (saved_at в файле обновляется)
      doSaveTemplateSet(action.name);
    }
  }

  function doSaveTemplateSet(name) {
    const layouts = state.pdf_settings?.custom_layouts || {};
    if (!Object.keys(layouts).length) {
      showNotification("Нет шаблонов для сохранения", "error");
      return;
    }
    flushAutoSave();
    callRuby("saveTemplateSet", JSON.stringify({ name: name, custom_layouts: deepClone(layouts) }));
  }

  function openSaveTemplateSetModal() {
    const layouts = state.pdf_settings?.custom_layouts || {};
    if (!Object.keys(layouts).length) {
      showNotification("Нет шаблонов для сохранения", "error");
      return;
    }
    if (els.inputTemplateSetName) {
      els.inputTemplateSetName.value = "";
    }
    if (els.saveTemplateSetModal) {
      els.saveTemplateSetModal.classList.remove("hidden");
      if (els.inputTemplateSetName) {
        setTimeout(() => els.inputTemplateSetName.focus(), 50);
      }
    }
  }

  function closeSaveTemplateSetModal() {
    if (els.saveTemplateSetModal) {
      els.saveTemplateSetModal.classList.add("hidden");
    }
  }

  function confirmSaveTemplateSet() {
    const name = (els.inputTemplateSetName ? els.inputTemplateSetName.value : "").trim();
    if (!name) {
      showNotification("Укажите название набора", "warning");
      if (els.inputTemplateSetName) els.inputTemplateSetName.focus();
      return;
    }
    closeSaveTemplateSetModal();

    // Набор с таким именем уже есть — подтверждаем перезапись
    const exists = (state.template_sets || []).some((s) => (s.name || "").toLowerCase() === name.toLowerCase());
    if (exists) {
      openConfirmTemplateSetModal({ type: "overwrite", name: name });
    } else {
      doSaveTemplateSet(name);
    }
  }

  function openRenameTemplateModal(tplKey) {
    if (!tplKey) {
      return;
    }
    templatePendingRename = tplKey;
    const tplDef = getTemplateDef(tplKey);
    if (els.inputRenameTemplateName) {
      els.inputRenameTemplateName.value = tplDef.name;
    }
    if (els.inputRenameTemplateDescription) {
      els.inputRenameTemplateDescription.value = tplDef.description || "";
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
    if (!tplKey) {
      closeRenameTemplateModal();
      return;
    }
    const newName = els.inputRenameTemplateName ? els.inputRenameTemplateName.value.trim() : "";
    if (!newName) {
      showNotification("Название шаблона не может быть пустым", "warning");
      if (els.inputRenameTemplateName) els.inputRenameTemplateName.focus();
      return;
    }
    const newDesc = els.inputRenameTemplateDescription ? els.inputRenameTemplateDescription.value.trim() : "";

    if (!state.pdf_settings) state.pdf_settings = {};
    if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
    if (!state.pdf_settings.custom_layouts[tplKey]) state.pdf_settings.custom_layouts[tplKey] = {};
    state.pdf_settings.custom_layouts[tplKey].name = newName;
    state.pdf_settings.custom_layouts[tplKey]._name = newName;
    state.pdf_settings.custom_layouts[tplKey].description = newDesc;
    state.pdf_settings.custom_layouts[tplKey]._description = newDesc;
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

// Слияние обновлений в конфиг блока шаблона (видовое окно и др.) с вкладки «Страницы»
function updateBlockSlot(blockId, updates, targetTplKey) {
  ensureCustomLayouts();
  const tplKey = targetTplKey || layoutState.currentTemplate || defaultTemplateKey();
  if (!state.pdf_settings.custom_layouts[tplKey]) {
    state.pdf_settings.custom_layouts[tplKey] = {};
  }
  const cur = state.pdf_settings.custom_layouts[tplKey][blockId];
  if (!cur || typeof cur !== "object") {
    state.pdf_settings.custom_layouts[tplKey][blockId] = {};
  }
  Object.assign(state.pdf_settings.custom_layouts[tplKey][blockId], deepClone(updates));
}

  // Синхронизация оверлея в SketchUp с выбранной сценой/страницей
  function syncCurrentSceneOverlay(scene, overrideRatio, isUserAction = false) {
    if (!scene) {
      const idx = layoutState.selectedSceneIndex || 0;
      scene = (state.scenes || [])[idx];
      if (!scene) return;
    }

    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "5:4", "1:1", "4:5", "custom"];
    let ratio = overrideRatio || scene.aspect_ratio || state.pdf_settings?.image_aspect_ratio || "4:3";
    ratio = String(ratio).trim();
    if (!VALID_ASPECT_RATIOS.includes(ratio)) {
      ratio = "4:3";
    }

    if (!isUserAction) return;

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A3").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const baseWidth = getEffectiveRenderWidth();

    const payload = {
      template_key: scene.page_type || "cover",
      scene_name: scene.name || "",
      scene_index: layoutState.selectedSceneIndex || 0,
      aspect_ratio: ratio,
      image_aspect_ratio: ratio,
      visible: true,
      scale_pct: scene.scale_pct || 100,
      page_size: pageSize,
      page_layout: pageLayout,
      image_width: baseWidth,
      show_aspect_overlay: scene.frame_overlay === true
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

    const tplKey = layoutState.currentTemplate || defaultTemplateKey();
    ensureCustomLayouts();
    const customLayouts = state.pdf_settings ? state.pdf_settings.custom_layouts || {} : {};
    const tplCfg = customLayouts[tplKey] || {};
    const imgCfg = tplCfg.image_4_3 || {};

    if (!isSlotVisible(imgCfg, true)) {
      if (state.pdf_settings) state.pdf_settings.show_aspect_overlay = false;
      if (isUserAction) {
        callRuby("toggleAspectOverlay", false);
      }
      return;
    }

    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "5:4", "1:1", "4:5", "custom"];
    let ratio = overrideRatio || imgCfg.aspect_ratio || state.pdf_settings?.image_aspect_ratio || "4:3";
    ratio = String(ratio).trim();
    if (!VALID_ASPECT_RATIOS.includes(ratio)) {
      ratio = state.pdf_settings?.image_aspect_ratio || "4:3";
      if (!VALID_ASPECT_RATIOS.includes(ratio)) {
        ratio = "4:3";
      }
    }

    // Отправка настроек в SketchUp происходит только при явном действии пользователя
    if (!isUserAction) {
      return;
    }

    const pageSize = (els.selectPageSize ? els.selectPageSize.value : "A3").toUpperCase();
    const pageLayout = (els.selectPageLayout ? els.selectPageLayout.value : "landscape").toLowerCase();
    const baseWidth = getEffectiveRenderWidth();

    const payload = {
      template_key: tplKey,
      aspect_ratio: ratio,
      image_aspect_ratio: ratio,
      custom_layouts: state.pdf_settings ? state.pdf_settings.custom_layouts : null,
      page_size: pageSize,
      page_layout: pageLayout,
      image_width: baseWidth,
      show_aspect_overlay: true
    };
    callRuby("updateAspectSettings", JSON.stringify(payload));
  }

// -----------------------------------------------------------------------------
// Template Settings Engine: карточка «Параметры страницы» (созданные параметры)
// -----------------------------------------------------------------------------

function getTemplateParams(tplKey) {
  ensureCustomLayouts();
  const key = tplKey || layoutState.currentTemplate || defaultTemplateKey();
  const cfg = state.pdf_settings.custom_layouts[key] || {};
  return Array.isArray(cfg.params) ? cfg.params : [];
}

function setTemplateParams(params, tplKey) {
  ensureCustomLayouts();
  const key = tplKey || layoutState.currentTemplate || defaultTemplateKey();
  if (!state.pdf_settings.custom_layouts[key]) {
    state.pdf_settings.custom_layouts[key] = {};
  }
  state.pdf_settings.custom_layouts[key].params = (params || []).map(normalizeTemplateParam);
}

// Общие настройки стека параметров шаблона: «размер между строками» (мм) и
// галочка «Линия» (тонкий разделитель между параметрами и блоками на листе).
// Задаются один раз в шапке карточки «Параметры страницы» и действуют на все
// строки шаблона (зеркало normalize_line_settings! в project_data.rb).
function getTemplateLineSettings(tplKey) {
  ensureCustomLayouts();
  const key = tplKey || layoutState.currentTemplate || defaultTemplateKey();
  const cfg = state.pdf_settings.custom_layouts[key] || {};
  const num = (v, def, min, max) => {
    const n = parseFloat(v);
    return isNaN(n) ? def : Math.min(max, Math.max(min, n));
  };
  const raw = cfg.line_enabled;
  return {
    line_gap: num(cfg.line_gap, 2.5, 0, 50),
    line_enabled: raw !== undefined && raw !== null &&
                  !(raw === false || raw === "false" || raw === 0 || raw === "0")
  };
}

function setTemplateLineSettings(tplKey, updates) {
  ensureCustomLayouts();
  const key = tplKey || layoutState.currentTemplate || defaultTemplateKey();
  if (!state.pdf_settings.custom_layouts[key]) {
    state.pdf_settings.custom_layouts[key] = {};
  }
  Object.assign(state.pdf_settings.custom_layouts[key], updates);
  notifyChange();
}

  function renderTemplateSettingsList(isUserAction = false) {
  if (!els.templateSettingsContainer) return;
  ensureCustomLayouts();
  syncDirectoriesSpecifications();

  const tplKey = layoutState.currentTemplate || (getAllTemplates()[0] ? getAllTemplates()[0].key : "");
  const tplDefObj = getTemplateDef(tplKey);
  const params = getTemplateParams(tplKey);
  const tplLine = getTemplateLineSettings(tplKey);

  if (els.currentTemplateTitle && tplKey) {
    els.currentTemplateTitle.textContent = tplDefObj.name;
  }
  // Все шаблоны равнозначны: удалить/переименовать можно любой
  if (els.btnDeleteCurrentTemplate) {
    els.btnDeleteCurrentTemplate.style.display = "inline-flex";
  }
  if (els.btnRenameCurrentTemplate) {
    els.btnRenameCurrentTemplate.style.display = "inline-flex";
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

    const sizeOptionsHtml = (current) => {
      const sizes = PARAM_FONT_SIZES.includes(current) ? PARAM_FONT_SIZES : PARAM_FONT_SIZES.concat([current]).sort((a, b) => a - b);
      return sizes.map((s) => `<option value="${s}" ${s === current ? "selected" : ""}>${s} pt</option>`).join("");
    };

    const gapOptionsHtml = (current) => {
      const gaps = PARAM_LINE_GAPS.includes(current) ? PARAM_LINE_GAPS : PARAM_LINE_GAPS.concat([current]).sort((a, b) => a - b);
      return gaps.map((g) => `<option value="${g}" ${g === current ? "selected" : ""}>${g} мм</option>`).join("");
    };

    const fontOptionsHtml = (current) => PARAM_FONT_FAMILIES
      .map((f) => `<option value="${f.value}" ${f.value === current ? "selected" : ""}>${f.label}</option>`).join("");

    const renderParamRowHtml = (p) => {
      const preview = paramPreviewValue(p.source);
      const previewShort = preview.replace(/\n+/g, " ⏎ ");
      // Подпись, которая реально печатается на листе: label или авто-подпись
      const shownLabel = p.show_label ? effectiveParamLabel(p.source, p.label) : "";
      return `
        <div class="tpl-param-row ${p.visible ? "" : "disabled-block"}" data-id="${p.id}">
          <div class="tpl-param-head">
            <span class="drag-handle tpl-param-drag" title="Перетащите, чтобы изменить порядок">⠿</span>
            <label class="tpl-param-vis" title="Выводить параметр на страницах шаблона">
              <input type="checkbox" class="tpl-param-visible" data-id="${p.id}" ${p.visible ? "checked" : ""}>
              <span>Вкл</span>
            </label>
            <div class="tpl-param-main">
              <span class="tpl-param-label">${paramSourceLabel(p.source)}</span>
              ${shownLabel ? `<span class="tpl-param-caption">«${shownLabel}»</span>` : ""}
              ${previewShort ? `<span class="tpl-line-preview">(${previewShort})</span>` : `<span class="tpl-line-preview tpl-param-preview-empty">(нет данных)</span>`}
            </div>
            <div class="tpl-param-actions">
              <button type="button" class="tpl-param-btn tpl-param-up" data-id="${p.id}" title="Выше в списке">▲</button>
              <button type="button" class="tpl-param-btn tpl-param-down" data-id="${p.id}" title="Ниже в списке">▼</button>
              <button type="button" class="tpl-param-btn tpl-param-edit" data-id="${p.id}" title="Изменить источник и заголовок"><i class="modus-icons" style="font-size: 13px;">edit</i></button>
              <button type="button" class="tpl-param-btn tpl-param-del" data-id="${p.id}" title="Удалить параметр"><i class="modus-icons" style="font-size: 13px;">delete</i></button>
            </div>
          </div>
          <div class="tpl-param-controls">
            <input type="color" class="tpl-param-color" data-id="${p.id}" value="${p.color}" title="Цвет текста параметра">
            <div class="tpl-param-box" title="Шрифт параметра («По умолчанию» — шрифт страницы)">
              <select class="tpl-param-select tpl-param-font" data-id="${p.id}">${fontOptionsHtml(p.font_family || "")}</select>
            </div>
            <div class="tpl-param-box" title="Размер шрифта (пт)">
              <select class="tpl-param-select tpl-param-size" data-id="${p.id}">${sizeOptionsHtml(p.font_size)}</select>
            </div>
            <div class="tpl-btn-group" title="Вертикальная привязка: группа у верхнего / нижнего края листа">
              <button type="button" class="tpl-param-btn tpl-param-valign ${p.valign !== "bottom" ? "active" : ""}" data-id="${p.id}" data-valign="top" title="По верху">⬆</button>
              <button type="button" class="tpl-param-btn tpl-param-valign ${p.valign === "bottom" ? "active" : ""}" data-id="${p.id}" data-valign="bottom" title="По низу">⬇</button>
            </div>
            <div class="tpl-btn-group" title="Колонка: слева / по центру / справа">
              <button type="button" class="tpl-param-btn tpl-param-align ${p.align === "left" ? "active" : ""}" data-id="${p.id}" data-align="left" title="Слева">⇤</button>
              <button type="button" class="tpl-param-btn tpl-param-align ${p.align === "center" ? "active" : ""}" data-id="${p.id}" data-align="center" title="По центру">↔</button>
              <button type="button" class="tpl-param-btn tpl-param-align ${p.align === "right" ? "active" : ""}" data-id="${p.id}" data-align="right" title="Справа">⇥</button>
            </div>
            <label class="tpl-param-vis" title="Выводить заголовок на отдельной строке над значением на листе">
              <input type="checkbox" class="tpl-param-show-label" data-id="${p.id}" ${p.show_label ? "checked" : ""}>
              <span>Заголовок</span>
            </label>
            <span class="tpl-param-zone" data-id="${p.id}" title="Зона размещения параметра на странице">${paramZoneLabel(p)}</span>
          </div>
        </div>
      `;
    };

    // Блок объединения параметров: вложенные параметры выводятся одной строкой
    // через « | » со стилем блока; внутри блока порядок меняется мышкой.
    const renderGroupHtml = (g) => {
      const children = Array.isArray(g.params) ? g.params : [];
      const childRows = children.map((c) => {
        const cPrev = paramPreviewValue(c.source).replace(/\n+/g, " ⏎ ");
        const cLabel = c.show_label ? effectiveParamLabel(c.source, c.label) : "";
        return `
          <div class="tpl-param-child" data-id="${c.id}">
            <span class="drag-handle tpl-param-drag" title="Перетащите, чтобы изменить порядок в блоке">⠿</span>
            <span class="tpl-param-child-label">${paramSourceLabel(c.source)}</span>
            ${cLabel ? `<span class="tpl-param-caption">«${cLabel}»</span>` : ""}
            ${cPrev ? `<span class="tpl-line-preview">(${cPrev})</span>` : `<span class="tpl-line-preview tpl-param-preview-empty">(нет данных)</span>`}
            <label class="tpl-param-vis tpl-param-child-vis" title="Выводить заголовок перед значением внутри блока">
              <input type="checkbox" class="tpl-param-child-show-label" data-id="${c.id}" ${c.show_label ? "checked" : ""}>
              <span>Заголовок</span>
            </label>
            <button type="button" class="tpl-param-child-out" data-id="${c.id}" data-group="${g.id}" title="Вывести из блока">${MODUS_CROSS_SVG}</button>
          </div>`;
      }).join("");

      return `
        <div class="tpl-param-row tpl-param-group ${g.visible ? "" : "disabled-block"}" data-id="${g.id}" data-group="true">
          <div class="tpl-param-head">
            <span class="drag-handle tpl-param-drag" title="Перетащите, чтобы изменить порядок">⠿</span>
            <label class="tpl-param-vis" title="Выводить блок на страницах шаблона">
              <input type="checkbox" class="tpl-param-visible" data-id="${g.id}" ${g.visible ? "checked" : ""}>
              <span>Вкл</span>
            </label>
            <div class="tpl-param-main">
              <span class="tpl-param-label"><i class="modus-icons" style="font-size: 13px; vertical-align: -1px; margin-right: 3px;">layers</i> Блок</span>
              <input type="text" class="form-control tpl-param-group-label" data-id="${g.id}" placeholder="Название блока (необязательно)" value="${g.label || ""}">
              <span class="tpl-param-count">${paramCountText(children.length)}</span>
            </div>
            <div class="tpl-param-actions">
              <button type="button" class="tpl-param-btn tpl-param-up" data-id="${g.id}" title="Выше в списке">▲</button>
              <button type="button" class="tpl-param-btn tpl-param-down" data-id="${g.id}" title="Ниже в списке">▼</button>
              <button type="button" class="tpl-param-btn tpl-param-del" data-id="${g.id}" title="Удалить блок вместе с его параметрами"><i class="modus-icons" style="font-size: 13px;">delete</i></button>
            </div>
          </div>
          <div class="tpl-param-controls">
            <input type="color" class="tpl-param-color" data-id="${g.id}" value="${g.color}" title="Цвет текста блока">
            <div class="tpl-param-box" title="Шрифт блока («По умолчанию» — шрифт страницы)">
              <select class="tpl-param-select tpl-param-font" data-id="${g.id}">${fontOptionsHtml(g.font_family || "")}</select>
            </div>
            <div class="tpl-param-box" title="Размер шрифта (пт)">
              <select class="tpl-param-select tpl-param-size" data-id="${g.id}">${sizeOptionsHtml(g.font_size)}</select>
            </div>
            <div class="tpl-btn-group" title="Вертикальная привязка: группа у верхнего / нижнего края листа">
              <button type="button" class="tpl-param-btn tpl-param-valign ${g.valign !== "bottom" ? "active" : ""}" data-id="${g.id}" data-valign="top" title="По верху">⬆</button>
              <button type="button" class="tpl-param-btn tpl-param-valign ${g.valign === "bottom" ? "active" : ""}" data-id="${g.id}" data-valign="bottom" title="По низу">⬇</button>
            </div>
            <div class="tpl-btn-group" title="Колонка: слева / по центру / справа">
              <button type="button" class="tpl-param-btn tpl-param-align ${g.align === "left" ? "active" : ""}" data-id="${g.id}" data-align="left" title="Слева">⇤</button>
              <button type="button" class="tpl-param-btn tpl-param-align ${g.align === "center" ? "active" : ""}" data-id="${g.id}" data-align="center" title="По центру">↔</button>
              <button type="button" class="tpl-param-btn tpl-param-align ${g.align === "right" ? "active" : ""}" data-id="${g.id}" data-align="right" title="Справа">⇥</button>
            </div>
            <label class="tpl-param-vis" title="Выводить название блока перед строкой на листе">
              <input type="checkbox" class="tpl-param-show-label" data-id="${g.id}" ${g.show_label ? "checked" : ""}>
              <span>Заголовок</span>
            </label>
            <span class="tpl-param-zone" data-id="${g.id}" title="Зона размещения блока на странице">${paramZoneLabel(g)}</span>
          </div>
          <div class="tpl-param-group-list" data-group-id="${g.id}">
            ${childRows || `<div class="tpl-param-drop-empty">Перетащите сюда параметры — они выстроятся в одну строку через « | »</div>`}
          </div>
        </div>
      `;
    };

    const rowsHtml = params.map((p) => (p.group ? renderGroupHtml(p) : renderParamRowHtml(p))).join("");

  const html = `
    <div class="tpl-single-column-layout">
      <div class="tpl-card" id="card_params">
        <div class="tpl-card-header">
          <div class="tpl-card-title-group">
            <span class="tpl-card-icon"><i class="modus-icons">tune</i></span>
            <span class="tpl-card-title">Параметры страницы</span>
          </div>
          <div class="tpl-card-header-actions">
            <label class="tpl-header-ctl" title="Размер между строками (мм) — общий отступ между параметрами и блоками на листе, один для всего шаблона">
              <span>Между строками</span>
              <select class="tpl-param-select tpl-header-linegap">${gapOptionsHtml(tplLine.line_gap)}</select>
            </label>
            <label class="tpl-header-ctl" title="Небольшая линия-разделитель между соседними строками параметров на листе, шириной с текст строки">
              <input type="checkbox" class="tpl-header-line" ${tplLine.line_enabled ? "checked" : ""}>
              <span>Линия</span>
            </label>
            <button type="button" class="btn btn-xs btn-secondary" id="btnCreateParamGroup" title="Создать блок объединения параметров: перетащенные в него параметры выстроятся в одну строку через « | »"><i class="modus-icons">layers</i> Блок</button>
            <button type="button" class="btn btn-xs btn-primary" id="btnCreateParam" title="Создать параметр шаблона"><i class="modus-icons">add_circle</i> Создать параметр</button>
          </div>
        </div>
        <div class="tpl-card-body">
            <p class="field-hint tpl-param-hint">Параметр создается из данных «Данные проекта», «Папки спецификации», сцены или страницы. Дополнительные настройки задаются в строке параметра: шрифт, размер, привязка по вертикали (⬆/⬇), выравнивание (⇤/↔/⇥), цвет и заголовок. «Размер между строками» и линия-разделитель «Линия» — общие для всех параметров и блоков, задаются в шапке карточки. Место на странице определяется выравниваниями: колонка слева/по центру/справа и привязка группы к верхнему или нижнему краю листа. 📦 Блок объединяет параметры в одну строку через « | ».</p>
          <div class="tpl-params-list">
            ${rowsHtml || `<div class="tpl-params-empty">Параметров пока нет — нажмите «+ Создать параметр».</div>`}
          </div>
        </div>
      </div>
    </div>
  `;

  els.templateSettingsContainer.innerHTML = html;
  bindTemplateSettingsEvents(tplKey);
  syncCurrentTemplateOverlay(null, isUserAction);
}

  // Drag-and-drop параметров: сортировка за ручку ⠿, перенос параметров в блок
  // и обратно, реордер внутри блока. Порядок в списке = порядок в зоне на листе;
  // порядок внутри блока = порядок в строке « | ».
  function setupParamDragAndDrop(container, tplKey) {
    const list = container.querySelector(".tpl-params-list");
    if (!list) return;
    const drag = { id: null, fromGroup: null }; // fromGroup: id блока либо null

    const clearMarkers = () => {
      list.querySelectorAll(".drag-over-top, .drag-over-bottom, .drag-over-group")
        .forEach((el) => el.classList.remove("drag-over-top", "drag-over-bottom", "drag-over-group"));
    };

    const findGroup = (params, gid) => params.find((p) => p.id === gid && p.group);

    // Реордер на верхнем уровне списка
    const reorderTopLevel = (dragId, targetId, before) => {
      const params = getTemplateParams(tplKey);
      const fromIdx = params.findIndex((p) => p.id === dragId);
      if (fromIdx < 0) return;
      const [moved] = params.splice(fromIdx, 1);
      const toIdx = params.findIndex((p) => p.id === targetId);
      if (toIdx < 0) {
        params.push(moved);
      } else {
        params.splice(before ? toIdx : toIdx + 1, 0, moved);
      }
      setTemplateParams(params, tplKey);
    };

    // Перенос параметра/дитя внутрь блока (в конец строки блока)
    const moveIntoGroup = (groupId, dragId, fromGroup) => {
      const params = getTemplateParams(tplKey);
      let moved = null;
      if (fromGroup === null) {
        const idx = params.findIndex((p) => p.id === dragId);
        if (idx < 0) return;
        [moved] = params.splice(idx, 1);
      } else {
        const src = findGroup(params, fromGroup);
        const cIdx = (src?.params || []).findIndex((c) => c.id === dragId);
        if (cIdx < 0) return;
        [moved] = src.params.splice(cIdx, 1);
      }
      const dst = findGroup(params, groupId);
      if (!dst) {
        params.push(moved);
      } else {
        (dst.params = Array.isArray(dst.params) ? dst.params : []).push(moved);
      }
      setTemplateParams(params, tplKey);
    };

    // Вывод дитя из блока на верхний уровень (перед/после целевой строки)
    const moveChildToTopLevel = (fromGroup, dragId, targetId, before) => {
      const params = getTemplateParams(tplKey);
      const src = findGroup(params, fromGroup);
      const cIdx = (src?.params || []).findIndex((c) => c.id === dragId);
      if (cIdx < 0) return;
      const [moved] = src.params.splice(cIdx, 1);
      const toIdx = params.findIndex((p) => p.id === targetId);
      if (toIdx < 0) {
        params.push(moved);
      } else {
        params.splice(before ? toIdx : toIdx + 1, 0, moved);
      }
      setTemplateParams(params, tplKey);
    };

    // Перенос к конкретному дитю: реордер внутри блока либо между блоками
    const moveChildToChild = (fromGroup, dragId, toGroup, targetChildId, before) => {
      const params = getTemplateParams(tplKey);
      let moved = null;

      if (fromGroup === toGroup) {
        const grp = findGroup(params, toGroup);
        const arr = grp.params = Array.isArray(grp.params) ? grp.params : [];
        const fromIdx = arr.findIndex((c) => c.id === dragId);
        if (fromIdx < 0) return;
        [moved] = arr.splice(fromIdx, 1);
        const toIdx = arr.findIndex((c) => c.id === targetChildId);
        if (toIdx < 0) arr.push(moved);
        else arr.splice(before ? toIdx : toIdx + 1, 0, moved);
        setTemplateParams(params, tplKey);
        return;
      }

      if (fromGroup === null) {
        const idx = params.findIndex((p) => p.id === dragId);
        if (idx < 0) return;
        [moved] = params.splice(idx, 1);
      } else {
        const src = findGroup(params, fromGroup);
        const cIdx = (src?.params || []).findIndex((c) => c.id === dragId);
        if (cIdx < 0) return;
        [moved] = src.params.splice(cIdx, 1);
      }

      const dst = findGroup(params, toGroup);
      if (!dst) {
        params.push(moved);
      } else {
        const arr = dst.params = Array.isArray(dst.params) ? dst.params : [];
        const toIdx = arr.findIndex((c) => c.id === targetChildId);
        if (toIdx < 0) arr.push(moved);
        else arr.splice(before ? toIdx : toIdx + 1, 0, moved);
      }
      setTemplateParams(params, tplKey);
    };

    // Общая обвязка событий перетаскивания для строки любого уровня.
    // Дети вложены в строку-блок, поэтому событие должно обрабатывать
    // только самая внутренняя строка, содержащая цель события.
    const wireRow = (row, groupId) => {
      const isOwnEvent = (e) => e.target.closest(".tpl-param-row, .tpl-param-child") === row;

      row.addEventListener("mousedown", (e) => {
        if (!isOwnEvent(e)) return;
        const interactive = e.target.closest("input, select, button, label, .tpl-btn-group");
        row.setAttribute("draggable", interactive ? "false" : "true");
      });
      row.addEventListener("mouseup", (e) => {
        if (!isOwnEvent(e)) return;
        row.setAttribute("draggable", "true");
      });

      row.addEventListener("dragstart", (e) => {
        if (!isOwnEvent(e)) return;
        drag.id = row.dataset.id;
        drag.fromGroup = groupId;
        row.classList.add("dragging");
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", row.dataset.id || "");
      });

      row.addEventListener("dragend", (e) => {
        if (!isOwnEvent(e)) return;
        drag.id = null;
        drag.fromGroup = null;
        row.classList.remove("dragging");
        clearMarkers();
      });
    };

    // 1. Верхнеуровневые строки (параметры и блоки)
    list.querySelectorAll(":scope > .tpl-param-row").forEach((row) => {
      wireRow(row, null);

      row.addEventListener("dragover", (e) => {
        if (!drag.id) return;
        if (e.target.closest(".tpl-param-group-list")) return; // подсветку дает список детей
        if (e.target.closest(".tpl-param-row") !== row) return; // событие из вложенной строки
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (drag.fromGroup === null && drag.id === row.dataset.id) return;
        const rect = row.getBoundingClientRect();
        const before = e.clientY < rect.top + rect.height / 2;
        row.classList.toggle("drag-over-top", before);
        row.classList.toggle("drag-over-bottom", !before);
      });

      row.addEventListener("dragleave", (e) => {
        if (e.target.closest(".tpl-param-row") !== row) return;
        row.classList.remove("drag-over-top", "drag-over-bottom");
      });

      row.addEventListener("drop", (e) => {
        if (e.target.closest(".tpl-param-row") !== row) return; // событие из вложенной строки
        if (!drag.id) return;
        e.preventDefault();
        e.stopPropagation();
        const targetId = row.dataset.id;
        const rect = row.getBoundingClientRect();
        const before = e.clientY < rect.top + rect.height / 2;
        row.classList.remove("drag-over-top", "drag-over-bottom");

        if (drag.fromGroup === null) {
          if (drag.id !== targetId) reorderTopLevel(drag.id, targetId, before);
        } else {
          moveChildToTopLevel(drag.fromGroup, drag.id, targetId, before);
        }
        drag.id = null;
        drag.fromGroup = null;
        renderTemplateSettingsList();
        notifyChange();
      });
    });

    // 2. Контейнер детей блока: бросок сюда переносит параметр в блок (в конец)
    list.querySelectorAll(":scope > .tpl-param-row[data-group='true'] > .tpl-param-group-list").forEach((glist) => {
      const groupId = glist.closest(".tpl-param-row").dataset.id;

      glist.addEventListener("dragover", (e) => {
        if (!drag.id) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        glist.classList.add("drag-over-group");
      });
      glist.addEventListener("dragleave", () => glist.classList.remove("drag-over-group"));
      glist.addEventListener("drop", (e) => {
        e.preventDefault();
        e.stopPropagation();
        glist.classList.remove("drag-over-group");
        if (!drag.id) return;
        const from = drag.fromGroup;
        const id = drag.id;
        drag.id = null;
        drag.fromGroup = null;
        if (!(from === groupId)) moveIntoGroup(groupId, id, from);
        renderTemplateSettingsList();
        notifyChange();
      });
    });

    // 3. Дети внутри блока: реордер, прием из других блоков/верхнего уровня
    list.querySelectorAll(".tpl-param-child").forEach((child) => {
      const parentGroup = child.closest(".tpl-param-row[data-group='true']")?.dataset.id || null;
      wireRow(child, parentGroup);

      child.addEventListener("dragover", (e) => {
        if (!drag.id) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (drag.fromGroup === parentGroup && drag.id === child.dataset.id) return;
        const rect = child.getBoundingClientRect();
        const before = e.clientY < rect.top + rect.height / 2;
        child.classList.toggle("drag-over-top", before);
        child.classList.toggle("drag-over-bottom", !before);
      });

      child.addEventListener("dragleave", () => child.classList.remove("drag-over-top", "drag-over-bottom"));

      child.addEventListener("drop", (e) => {
        if (!drag.id) return;
        e.preventDefault();
        e.stopPropagation();
        child.classList.remove("drag-over-top", "drag-over-bottom");
        const rect = child.getBoundingClientRect();
        const before = e.clientY < rect.top + rect.height / 2;
        const from = drag.fromGroup;
        const id = drag.id;
        drag.id = null;
        drag.fromGroup = null;
        moveChildToChild(from, id, parentGroup, child.dataset.id, before);
        renderTemplateSettingsList();
        notifyChange();
      });
    });
  }

  function bindTemplateSettingsEvents(tplKey) {
  if (!els.templateSettingsContainer) return;
  const container = els.templateSettingsContainer;

    const btnCreate = document.getElementById("btnCreateParam");
    if (btnCreate) {
      btnCreate.addEventListener("click", () => openParamModal("create", null, tplKey));
    }

    const btnCreateGroup = document.getElementById("btnCreateParamGroup");
    if (btnCreateGroup) {
      btnCreateGroup.addEventListener("click", () => createParamGroup(tplKey));
    }

  container.querySelectorAll(".tpl-param-visible").forEach((chk) => {
    chk.addEventListener("change", () => {
      const id = chk.dataset.id;
      const params = getTemplateParams(tplKey).map((p) => (p.id === id ? Object.assign({}, p, { visible: chk.checked }) : p));
      setTemplateParams(params, tplKey);
      const row = container.querySelector(`.tpl-param-row[data-id="${id}"]`);
      if (row) row.classList.toggle("disabled-block", !chk.checked);
      notifyChange();
    });
  });

  container.querySelectorAll(".tpl-param-edit").forEach((btn) => {
    btn.addEventListener("click", () => openParamModal("edit", btn.dataset.id, tplKey));
  });

  container.querySelectorAll(".tpl-param-del").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.id;
      setTemplateParams(getTemplateParams(tplKey).filter((p) => p.id !== id), tplKey);
      renderTemplateSettingsList();
      notifyChange();
    });
  });

  const moveParam = (id, delta) => {
    const params = getTemplateParams(tplKey);
    const idx = params.findIndex((p) => p.id === id);
    const target = idx + delta;
    if (idx < 0 || target < 0 || target >= params.length) return;
    const swapped = [...params];
    [swapped[idx], swapped[target]] = [swapped[target], swapped[idx]];
    setTemplateParams(swapped, tplKey);
    renderTemplateSettingsList();
    notifyChange();
  };
    container.querySelectorAll(".tpl-param-up").forEach((btn) => {
      btn.addEventListener("click", () => moveParam(btn.dataset.id, -1));
    });
    container.querySelectorAll(".tpl-param-down").forEach((btn) => {
      btn.addEventListener("click", () => moveParam(btn.dataset.id, 1));
    });

    // Перетаскивание параметров за ручку ⠿ меняет их порядок в списке
    setupParamDragAndDrop(container, tplKey);

    // Дополнительные настройки параметра задаются прямо в строке:
    // шрифт, размер, привязка по вертикали, выравнивание, цвет, заголовок.
    // «Размер между строками» и «Линия» — общие, в шапке карточки.
    const updateParam = (id, updates) => {
      const params = getTemplateParams(tplKey).map((p) => (p.id === id ? Object.assign({}, p, updates) : p));
      setTemplateParams(params, tplKey);
      notifyChange();
      return params.find((p) => p.id === id);
    };

    const refreshZoneLabel = (param) => {
      if (!param) return;
      const zone = container.querySelector(`.tpl-param-zone[data-id="${param.id}"]`);
      if (zone) zone.textContent = paramZoneLabel(param);
    };

    container.querySelectorAll(".tpl-param-font").forEach((sel) => {
      sel.addEventListener("change", () => updateParam(sel.dataset.id, { font_family: sel.value }));
    });

    container.querySelectorAll(".tpl-param-size").forEach((sel) => {
      sel.addEventListener("change", () => {
        const sz = parseFloat(sel.value);
        if (!isNaN(sz) && sz > 0) updateParam(sel.dataset.id, { font_size: sz });
      });
    });

    // Общие настройки стека параметров (шапка карточки): линия-разделитель
    // и размер между строками — одни на все параметры и блоки шаблона
    const headerLineChk = container.querySelector(".tpl-header-line");
    if (headerLineChk) {
      headerLineChk.addEventListener("change", () => {
        setTemplateLineSettings(tplKey, { line_enabled: headerLineChk.checked });
      });
    }

    const headerGapSel = container.querySelector(".tpl-header-linegap");
    if (headerGapSel) {
      headerGapSel.addEventListener("change", () => {
        const g = parseFloat(headerGapSel.value);
        if (!isNaN(g) && g >= 0) setTemplateLineSettings(tplKey, { line_gap: g });
      });
    }

    container.querySelectorAll(".tpl-param-valign").forEach((btn) => {
      btn.addEventListener("click", () => {
        const group = btn.closest(".tpl-btn-group");
        if (group) group.querySelectorAll(".tpl-param-valign").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        refreshZoneLabel(updateParam(btn.dataset.id, { valign: btn.dataset.valign }));
      });
    });

    container.querySelectorAll(".tpl-param-align").forEach((btn) => {
      btn.addEventListener("click", () => {
        const group = btn.closest(".tpl-btn-group");
        if (group) group.querySelectorAll(".tpl-param-align").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        refreshZoneLabel(updateParam(btn.dataset.id, { align: btn.dataset.align }));
      });
    });

    container.querySelectorAll(".tpl-param-color").forEach((inp) => {
      const onColorChange = () => updateParam(inp.dataset.id, { color: inp.value });
      inp.addEventListener("input", onColorChange);
      inp.addEventListener("change", onColorChange);
    });

    container.querySelectorAll(".tpl-param-show-label").forEach((chk) => {
      chk.addEventListener("change", () => {
        updateParam(chk.dataset.id, { show_label: chk.checked });
        // Заголовок отображается в шапке строки («Название» источника) — перерисуем
        renderTemplateSettingsList();
      });
    });

    // Название блока: сохраняем на лету, без перерисовки (иначе собьется ввод)
    container.querySelectorAll(".tpl-param-group-label").forEach((inp) => {
      inp.addEventListener("input", () => updateParam(inp.dataset.id, { label: inp.value }));
    });

    // ✕ у параметра внутри блока — вывести его из блока обратно в общий список
    container.querySelectorAll(".tpl-param-child-out").forEach((btn) => {
      btn.addEventListener("click", () => {
        const params = getTemplateParams(tplKey);
        const group = params.find((p) => p.id === btn.dataset.group && p.group);
        if (!group || !Array.isArray(group.params)) return;
        const cIdx = group.params.findIndex((c) => c.id === btn.dataset.id);
        if (cIdx < 0) return;
        const [child] = group.params.splice(cIdx, 1);
        params.push(child);
        setTemplateParams(params, tplKey);
        renderTemplateSettingsList();
        notifyChange();
      });
    });

    // «Заголовок» у параметра внутри блока: подпись ребёнка печатается перед
    // его значением внутри строки блока («Помещение: Гостиная | Адрес: …»)
    container.querySelectorAll(".tpl-param-child-show-label").forEach((chk) => {
      chk.addEventListener("change", () => {
        const params = getTemplateParams(tplKey);
        const group = params.find((p) => p.group && Array.isArray(p.params) && p.params.some((c) => c.id === chk.dataset.id));
        if (!group) return;
        group.params = group.params.map((c) => (c.id === chk.dataset.id ? Object.assign({}, c, { show_label: chk.checked }) : c));
        setTemplateParams(params, tplKey);
        notifyChange();
        // Подпись в строке ребёнка могла появиться или исчезнуть — перерисуем
        renderTemplateSettingsList();
      });
    });
  }

// -------------------------------------------------------------
// Модал создания/редактирования параметра шаблона
// (разметка — Vue-компонент ParamModal.vue, форма — ui-store)
// -------------------------------------------------------------
let paramModalState = { mode: "create", id: null, tplKey: null };

function updateParamModalPreview() {
  const val = paramPreviewValue(ui.paramModal.source).replace(/\n+/g, " ⏎ ");
  ui.paramModal.preview = val ? `Пример: ${val}` : "Данные не заполнены — параметр не будет выведен на лист";
  ui.paramModal.previewEmpty = !val;
  // Подсказка в поле заголовка: что напечатается, если оставить его пустым
  const auto = effectiveParamLabel(ui.paramModal.source, "");
  ui.paramModal.labelPlaceholder = auto ? `Авто: ${auto}` : "Заголовок (авто-подпись недоступна)";
}

  function openParamModal(mode, paramId, tplKey) {
    paramModalState = { mode: mode, id: paramId || null, tplKey: tplKey || layoutState.currentTemplate || defaultTemplateKey() };

    const existing = mode === "edit" ? getTemplateParams(paramModalState.tplKey).find((p) => p.id === paramId) : null;
    const sources = buildParamSources();
    const firstSource = sources[0] && sources[0].options[0] ? sources[0].options[0].value : "";

    ui.paramModal.mode = mode;
    ui.paramModal.id = paramModalState.id;
    ui.paramModal.tplKey = paramModalState.tplKey;
    ui.paramModal.title = mode === "edit" ? "Редактировать параметр" : "Создать параметр";
    ui.paramModal.sources = sources;
    ui.paramModal.source = existing ? existing.source : firstSource;
    ui.paramModal.label = existing ? existing.label : "";
    updateParamModalPreview();
    ui.paramModal.visible = true;
  }

  function closeParamModal() {
    ui.paramModal.visible = false;
    paramModalState = { mode: "create", id: null, tplKey: null };
  }

  function confirmParamModal() {
    const source = ui.paramModal.source;
    if (!source) {
      showNotification("Выберите источник данных", "warning");
      return;
    }

    const isEdit = paramModalState.mode === "edit";
    // Шрифт, размер, выравнивания, цвет, заголовок и «Вкл» задаются в строке
    // параметра; место на странице определяется выравниваниями.
    const existing = isEdit ? getTemplateParams(paramModalState.tplKey).find((p) => p.id === paramModalState.id) : null;
    const value = {
      id: paramModalState.id || undefined,
      source: source,
      label: ui.paramModal.label.trim(),
      show_label: existing ? existing.show_label : true,
      align: existing ? existing.align : DEFAULT_PARAM_SETTINGS.align,
      valign: existing ? existing.valign : DEFAULT_PARAM_SETTINGS.valign,
      font_family: existing ? existing.font_family : DEFAULT_PARAM_SETTINGS.font_family,
      font_size: existing ? existing.font_size : DEFAULT_PARAM_SETTINGS.font_size,
      color: existing ? existing.color : DEFAULT_PARAM_SETTINGS.color,
      visible: existing ? existing.visible : true
    };
    const normalized = normalizeTemplateParam(value);

    const params = getTemplateParams(paramModalState.tplKey);
    if (isEdit) {
      const idx = params.findIndex((p) => p.id === paramModalState.id);
      if (idx >= 0) params[idx] = normalized;
      else params.push(normalized);
    } else {
      params.push(normalized);
    }
    setTemplateParams(params, paramModalState.tplKey);

    closeParamModal();
    renderTemplateSettingsList();
    notifyChange();
    showNotification(isEdit ? "Параметр обновлен" : "Параметр создан", "success");
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

    // Динамический список основ нового шаблона: текущие шаблоны + «Пустой шаблон»
    function syncNewTemplateBaseSelect() {
      if (!els.selectNewTemplateBase) return;
      const prevVal = els.selectNewTemplateBase.value;
      els.selectNewTemplateBase.innerHTML = "";
      const emptyOpt = document.createElement("option");
      emptyOpt.value = "empty";
      emptyOpt.textContent = "Пустой шаблон — базовый видовой экран";
      els.selectNewTemplateBase.appendChild(emptyOpt);
      getAllTemplates().forEach((t) => {
        const opt = document.createElement("option");
        opt.value = t.key;
        opt.textContent = t.name;
        els.selectNewTemplateBase.appendChild(opt);
      });
      const hasPrev = Array.from(els.selectNewTemplateBase.options).some((o) => o.value === prevVal);
      els.selectNewTemplateBase.value = hasPrev ? prevVal : "empty";
    }

    // Modal and Template Management Buttons
    if (els.btnCreateTemplate) {
      els.btnCreateTemplate.addEventListener("click", () => {
        if (els.newTemplateModal) {
          if (els.inputNewTemplateName) els.inputNewTemplateName.value = "";
          if (els.inputNewTemplateDescription) els.inputNewTemplateDescription.value = "";
          syncNewTemplateBaseSelect();
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
        const baseType = els.selectNewTemplateBase ? els.selectNewTemplateBase.value : "empty";
        const description = els.inputNewTemplateDescription ? els.inputNewTemplateDescription.value.trim() : "";
        if (!name) {
          showNotification("Введите название шаблона", "warning");
          if (els.inputNewTemplateName) els.inputNewTemplateName.focus();
          return;
        }
        createCustomTemplate(name, baseType, description);
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

    if (els.inputNewTemplateDescription) {
      els.inputNewTemplateDescription.addEventListener("keydown", (e) => {
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

    if (els.inputRenameTemplateDescription) {
      els.inputRenameTemplateDescription.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          confirmRenameTemplate();
        } else if (e.key === "Escape") {
          closeRenameTemplateModal();
        }
      });
    }

    // Template Sets Handlers (наборы шаблонов)
    if (els.btnSaveTemplateSet) {
      els.btnSaveTemplateSet.addEventListener("click", () => {
        openSaveTemplateSetModal();
      });
    }

    if (els.btnCancelSaveTemplateSet) {
      els.btnCancelSaveTemplateSet.addEventListener("click", () => {
        closeSaveTemplateSetModal();
      });
    }

    if (els.btnConfirmSaveTemplateSet) {
      els.btnConfirmSaveTemplateSet.addEventListener("click", () => {
        confirmSaveTemplateSet();
      });
    }

    if (els.inputTemplateSetName) {
      els.inputTemplateSetName.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          confirmSaveTemplateSet();
        } else if (e.key === "Escape") {
          closeSaveTemplateSetModal();
        }
      });
    }

    if (els.btnCancelConfirmTemplateSet) {
      els.btnCancelConfirmTemplateSet.addEventListener("click", () => {
        closeConfirmTemplateSetModal();
      });
    }

    if (els.btnConfirmTemplateSet) {
      els.btnConfirmTemplateSet.addEventListener("click", () => {
        confirmTemplateSetAction();
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

    // Reset Layout Button: сброс шаблона к дефолту (видовое окно + пустой список параметров)
    if (els.btnResetLayout) {
      els.btnResetLayout.addEventListener("click", () => {
        const tplKey = layoutState.currentTemplate;
        const tplDefObj = getTemplateDef(tplKey);
        const defTpl = DEFAULT_LAYOUTS[tplKey] || DEFAULT_LAYOUTS[tplDefObj.baseType] || DEFAULT_LAYOUTS.cover;
        if (!defTpl) return;

        if (!state.pdf_settings.custom_layouts) state.pdf_settings.custom_layouts = {};
        const prevMeta = {};
        const curCfg = state.pdf_settings.custom_layouts[tplKey];
        if (curCfg) {
          ["name", "_name", "description", "_description", "_base_type", "_icon", "_meta"].forEach((k) => {
            if (curCfg[k] !== undefined) prevMeta[k] = curCfg[k];
          });
        }
        state.pdf_settings.custom_layouts[tplKey] = Object.assign({}, prevMeta, {
          image_4_3: deepClone(defTpl.image_4_3 || DEFAULT_IMAGE_SLOT),
          params: []
        });

        renderTemplateSettingsList();
        renderTemplatesList();
        showNotification(`Настройки шаблона «${tplDefObj.name}» сброшены к стандартам`, "success");
        notifyChange();
      });
    }

    // Параметр шаблона: модал создания/редактирования перенесён в Vue-компонент
    // ParamModal.vue — события (отмена/сохранение/ESC/Enter/смена источника)
    // обрабатываются там и приходят через window.legacy.

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
    els.headerTradeBadge.innerHTML = !hasArticul
      ? "Тип не выбран"
      : (isCommercial ? '<i class="modus-icons" style="font-size: 13px; vertical-align: -1px; margin-right: 3px;">user_group</i> Коммерческий' : '<i class="modus-icons" style="font-size: 13px; vertical-align: -1px; margin-right: 3px;">account</i> Бытовой');
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
    if (els.inputCompany) els.inputCompany.value = cust.company || prj.name_company || info.company || "";
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
    if (els.inputRate) els.inputRate.value = wf.rate || info.rate || "";
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
    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "5:4", "1:1", "4:5", "custom"];
    let initialAspect = settings.image_aspect_ratio;
    if (!VALID_ASPECT_RATIOS.includes(initialAspect)) {
      initialAspect = "4:3";
    }
    if (els.selectImageAspect) els.selectImageAspect.value = initialAspect;
    if (els.inputAspectCustomW) els.inputAspectCustomW.value = settings.custom_ratio_w || 16;
    if (els.inputAspectCustomH) els.inputAspectCustomH.value = settings.custom_ratio_h || 9;
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
    selectTemplate(layoutState.currentTemplate || defaultTemplateKey());
    updateLayoutUsageBadge();
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
      const entry = ui.directories[index];
      if (entry && entry.preview && entry.preview.state === "loading") {
        entry.preview = { state: "timeout", files: [], count: 0 };
      }
    }, 4500);
  }

  // Пересканирует файлы одной папки: сбрасывает кеш и предпросмотр, запрашивает
  // список файлов у Ruby. Используется общей кнопкой «Обновить» в заголовке секции.
  // @return [Boolean] false, если у папки не указан путь
  function refreshDirectoryFiles(index) {
    const d = state.directories[index];
    if (!d || !d.path) return false;
    const entry = ui.directories[index];
    if (entry) entry.preview = defaultDirPreview();
    if (state.folderFiles) delete state.folderFiles[index];
    if (state.folderFilesByPath && d.path) delete state.folderFilesByPath[d.path];
    scheduleScanTimeout(index, d.path);
    callRuby("getFolderFiles", JSON.stringify({ index: index, path: d.path }));
    return true;
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

  // Render Project Directories: источник — state.directories, рендер — Vue-компонент
  // DirectoriesTab.vue через ui.directories (../store.js). Здесь только синхронизация
  // и запрос списков файлов у Ruby.
  function renderDirectories() {
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

    syncDirectoriesUI();
  }

  // Копирует state.directories в ui.directories, сохраняя uid и предпросмотр
  // для карточек, чьи путь/индекс не изменились; запускает сканирование папок.
  function syncDirectoriesUI() {
    const oldEntries = ui.directories;
    ui.directories = state.directories.map((d, index) => {
      const prev = oldEntries[index];
      const pathUnchanged = prev && prev.path === (d.path || "");
      const thumbSize = ["small", "medium", "large"].includes(d.thumb_size) ? d.thumb_size : "medium";
      d.thumb_size = thumbSize;
      return {
        uid: pathUnchanged ? prev.uid : nextDirUid(),
        path: d.path || "",
        title: d.title || "",
        description: d.description || "",
        send_to_server: d.send_to_server !== false,
        thumb_size: thumbSize,
        preview: pathUnchanged ? prev.preview : defaultDirPreview()
      };
    });

    ui.directories.forEach((entry, index) => {
      if (!entry.path) {
        entry.preview = { state: "nopath", files: [], count: 0 };
        return;
      }
      const cached = (state.folderFiles && state.folderFiles[index] && state.folderFiles[index].path === entry.path)
        ? state.folderFiles[index]
        : (state.folderFilesByPath ? state.folderFilesByPath[entry.path] : null);
      if (cached) {
        state.folderFiles[index] = cached;
        renderDirectoryPreview(index, cached);
      } else {
        scheduleScanTimeout(index, entry.path);
        callRuby("getFolderFiles", JSON.stringify({ index: index, path: entry.path }));
      }
    });
  }

  // Commit из Vue-компонента: принимает plain-копию ui.directories
  // (порядок и поля уже изменены пользователем)
  function commitDirectories(plainList) {
    state.directories = plainList;
    syncDirectoriesSpecifications();
    // sync может подтянуть описания из project_info — возвращаем их в ui
    plainList.forEach((d, i) => {
      const entry = ui.directories[i];
      if (entry && entry.description !== d.description) entry.description = d.description;
    });
    notifyChange();
  }

  // Кнопка «Добавить папку» (теперь из DirectoriesTab.vue)
  function addDirectory() {
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
    const container = document.querySelector(".directories-cards-container");
    const cards = container ? container.querySelectorAll(".directory-card") : [];
    if (cards.length > 0) {
      cards[cards.length - 1].scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
    // Сразу открываем проводник для выбора папки у новой карточки:
    // после выбора путь и заголовок из имени папки придут в onDirectorySelected
    callRuby("selectDirectory", newIndex.toString());
  }

  // Кнопка «Обновить»: пересканирует файлы во всех папках с указанным путём
  function refreshDirectories() {
    const dirs = Array.isArray(state.directories) ? state.directories : [];
    if (dirs.length === 0) {
      showNotification("Нет папок для обновления", "warning");
      return;
    }
    let refreshed = 0;
    dirs.forEach((d, index) => {
      if (refreshDirectoryFiles(index)) refreshed++;
    });
    if (refreshed === 0) {
      showNotification("Укажите путь к папке", "warning");
    } else {
      showNotification(`Обновление файлов: папок ${refreshed}`, "info");
    }
  }

  // Render file previews for a specific directory card (пишет в ui.directories,
  // рендер — DirectoriesTab.vue)
  function renderDirectoryPreview(index, data) {
    clearScanTimeout(index);
    const entry = ui.directories[index];
    if (!entry) return;

    if (!data.exists) {
      entry.preview = { state: "missing", files: [], count: 0 };
      return;
    }

    const files = data.files || [];
    entry.preview = { state: files.length > 0 ? "ready" : "empty", files: files, count: files.length };
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
      icon.innerHTML = '<i class="modus-icons">web_link</i>';

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
      btnDelete.innerHTML = MODUS_CROSS_SVG;
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
    const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "5:4", "1:1", "4:5", "custom"];
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
    } else if (aspectMode === "5:4") {
      ratio = 5.0 / 4.0;
      label = "5:4 (Альбомный)";
    } else if (aspectMode === "4:5") {
      ratio = 4.0 / 5.0;
      label = "4:5 (Портретный)";
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

    if (els.headerProjectTitle) {
      els.headerProjectTitle.textContent = pTitle;
      // Плейсхолдер приглушается, чтобы не выглядеть настоящими данными
      els.headerProjectTitle.classList.toggle("is-placeholder", parts.length === 0);
    }
    if (els.headerProjectSubtitle) {
      els.headerProjectSubtitle.textContent = subText;
      els.headerProjectSubtitle.classList.toggle("is-placeholder", subParts.length === 0);
    }

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
  let sceneThumbnailsSig = null;
  let sceneThumbsManualRequest = false;

  // Сигнатура набора сцен: состав/имена/порядок страниц и флаги «Фон»/«Водяной знак».
  // Эскизы перегенерируются автоматически только когда она меняется —
  // иначе SketchUp зря «перелистывает» все страницы при каждом открытии вкладки
  function sceneThumbnailsSignature() {
    const scenes = state.scenes || [];
    return JSON.stringify(scenes.map((s) => [s.name || "", s.original_name || "", s.viewport_background === true, s.viewport_watermarks === true]));
  }

  function requestSceneThumbnails(force) {
    if (sceneThumbnailsInFlight) return;
    const sig = sceneThumbnailsSignature();
    if (!force && requestedSceneThumbnails && sig === sceneThumbnailsSig) return;
    requestedSceneThumbnails = true;
    sceneThumbnailsInFlight = true;
    callRuby("getSceneThumbnails");
  }

  // Актуализировать список страниц из модели SketchUp при открытии вкладки
  // «Страницы» (новые страницы добавляются, удалённые убираются),
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

    // Пересылаем параметры кадра выбранной страницы (рамка теперь постраничная)
    syncCurrentSceneOverlay(scene, null, true);
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

  // Update frame menu button label in scenes table row
  function updateSceneTableAspectCell(index, ratio) {
    if (!els.scenesTableBody) return;
    const row = els.scenesTableBody.querySelector(`tr[data-index="${index}"]`);
    if (!row) return;
    const frameBtn = row.querySelector(".scene-frame-btn");
    if (frameBtn) {
      const r = (ratio || "4:3").trim();
      const label = frameBtn.querySelector(".scene-frame-ratio");
      if (label) label.textContent = r.toLowerCase() === "page" ? "По листу" : r;
    }
  }

  // Обновить индикаторы рамки кадра во всех строках таблицы (без перерендера таблицы)
  function updateSceneTableFrameStates() {
    if (!els.scenesTableBody) return;
    const rows = els.scenesTableBody.querySelectorAll("tr");
    rows.forEach((row) => {
      const idx = parseInt(row.dataset.index, 10);
      const scene = (state.scenes || [])[idx];
      if (!scene) return;
      const btn = row.querySelector(".scene-frame-btn");
      if (btn) btn.classList.toggle("frame-on", scene.frame_overlay === true);
      const chk = row.querySelector(".scene-frame-check");
      if (chk) chk.checked = scene.frame_overlay === true;
    });
  }

  // -------------------------------------------------------------
  // Выравнивание эскиза на странице — постраничная настройка, сетка 3×3
  // -------------------------------------------------------------
  const ALIGN_GLYPHS = {
    "left|top": "↖", "center|top": "↑", "right|top": "↗",
    "left|center": "←", "center|center": "•", "right|center": "→",
    "left|bottom": "↙", "center|bottom": "↓", "right|bottom": "↘"
  };
  const SCENE_ALIGN_H = ["left", "center", "right"];
  const SCENE_ALIGN_V = ["top", "center", "bottom"];

  function alignGlyph(h, v) {
    return ALIGN_GLYPHS[`${h}|${v}`] || "•";
  }

  function sceneAlignTitle(h, v) {
    const H = { left: "по левому краю", center: "по центру", right: "по правому краю" };
    const V = { top: "по верху", center: "по центру", bottom: "по низу" };
    if (h === "center" && v === "center") return "по центру страницы";
    if (v === "center") return `по горизонтали ${H[h] || h}`;
    if (h === "center") return `по вертикали ${V[v] || v}`;
    return `${H[h] || h} · ${V[v] || v}`;
  }

  function closeSceneAlignPopover() {
    const pop = document.getElementById("sceneAlignPopover");
    if (pop) pop.remove();
    document.removeEventListener("click", closeSceneAlignPopover);
    document.removeEventListener("keydown", closeSceneAlignPopover);
  }

  function closeSceneFramePopover() {
    const pop = document.getElementById("sceneFramePopover");
    if (pop) pop.remove();
    document.removeEventListener("click", closeSceneFramePopover);
    document.removeEventListener("keydown", closeSceneFramePopover);
  }

  // Create mini page preview element for a scene (3:2 clean image, no blue lines)
  function createMiniPagePreview(scene, index) {
    const tplKey = scene.page_type || "cover";
    const tplDefObj = getTemplateDef(tplKey);
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
      placeholder.innerHTML = `<span class="mini-sheet-placeholder-icon"><i class="modus-icons" style="font-size: 18px; color: var(--text-dim, #6a6e79);">insert_photo</i></span>`;
      thumbBox.appendChild(placeholder);
    }

    // Click on thumbnail switches scene in SketchUp (stays on current tab)
    thumbBox.addEventListener("click", (e) => {
      e.stopPropagation();
      layoutState.selectedSceneIndex = index;
      selectTemplate(scene.page_type || "cover");
      highlightActiveSceneRow(index);
      switchToSketchupScene(scene, index);
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

  // Render Scenes Table
  function renderScenesTable() {
    els.scenesTableBody.innerHTML = "";
    const scenes = state.scenes || [];
    updateSceneBadge();

    // Синхронизация глобальных галок фона и водяных знаков в тулбаре со состоянием сцен
    if (els.chkScenesBackground) {
      els.chkScenesBackground.checked = scenes.some((s) => s.viewport_background === true);
    }
    if (els.chkScenesWatermarks) {
      els.chkScenesWatermarks.checked = scenes.some((s) => s.viewport_watermarks === true);
    }

    // «Кадр все» отмечен, когда рамка включена на всех страницах
    if (els.chkScenesFrameAll) {
      els.chkScenesFrameAll.checked = scenes.length > 0 && scenes.every((s) => s.frame_overlay === true);
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

      // 4. Frame Cell (Кадр) — постраничные пропорции и рамка кадра (меню)
      const tdAspect = document.createElement("td");
      tdAspect.className = "scene-aspect-cell";
      const ASPECT_OPTIONS = [["3:2", "3:2"], ["4:3", "4:3"], ["5:4", "5:4"], ["16:9", "16:9"], ["1:1", "1:1"], ["4:5", "4:5"], ["page", "По листу"]];
      const curRatio = (scene.aspect_ratio || "4:3").trim();
      const sceneRatio = ASPECT_OPTIONS.some(([val]) => val === curRatio) ? curRatio : "4:3";
      const ratioLabel = (val) => (String(val).toLowerCase() === "page" ? "По листу" : val);

      const frameBtn = document.createElement("button");
      frameBtn.type = "button";
      frameBtn.className = "scene-frame-btn" + (scene.frame_overlay === true ? " frame-on" : "");
      frameBtn.innerHTML =
        `<span class="scene-frame-ratio">${ratioLabel(sceneRatio)}</span>` +
        `<span class="scene-frame-dot"></span>` +
        `<i class="modus-icons scene-frame-caret">expand_more</i>`;
      frameBtn.title = "Пропорции кадра для этой страницы";
      frameBtn.addEventListener("focus", () => {
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });

      // Рамка кадра — постраничный флаг отображения Safe Frame Overlay в окне SketchUp
      const frameChk = document.createElement("input");
      frameChk.type = "checkbox";
      frameChk.className = "scene-frame-check";
      frameChk.checked = scene.frame_overlay === true;
      frameChk.title = "Рамка кадра для этой страницы (вкл/выкл)";
      frameChk.addEventListener("click", (e) => e.stopPropagation());
      frameChk.addEventListener("change", (ev) => {
        const on = ev.target.checked;
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
        scene.frame_overlay = on;
        frameBtn.classList.toggle("frame-on", on);
        callRuby("toggleAspectOverlay", JSON.stringify({ enabled: on, scene_index: index }));
        if (on && layoutState.selectedSceneIndex === index) {
          syncCurrentSceneOverlay(scene, null, true);
        }
        notifyChange();
      });

      frameBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);

        const existing = document.getElementById("sceneFramePopover");
        if (existing) {
          closeSceneFramePopover();
          return;
        }
        const pop = document.createElement("div");
        pop.id = "sceneFramePopover";
        pop.className = "scene-frame-pop";
        pop.addEventListener("click", (ev) => ev.stopPropagation());

        // Пропорции кадра
        const ratioTitle = document.createElement("div");
        ratioTitle.className = "scene-frame-pop-title";
        ratioTitle.textContent = "Пропорции кадра";
        pop.appendChild(ratioTitle);

        const ratioGrid = document.createElement("div");
        ratioGrid.className = "scene-frame-ratio-grid";
        ASPECT_OPTIONS.forEach(([val, label]) => {
          const optBtn = document.createElement("button");
          optBtn.type = "button";
          optBtn.className = "scene-frame-ratio-opt" + (val === sceneRatio ? " active" : "");
          optBtn.textContent = label;
          optBtn.title = `Пропорции кадра ${label}`;
          optBtn.addEventListener("click", (ev) => {
            ev.stopPropagation();
            // Пропорции — персональная настройка страницы (scene.aspect_ratio);
            // в блок шаблона не пишем, чтобы не менять другие страницы шаблона
            scene.aspect_ratio = val;
            const labelSpan = frameBtn.querySelector(".scene-frame-ratio");
            if (labelSpan) labelSpan.textContent = ratioLabel(val);
            pop.querySelectorAll(".scene-frame-ratio-opt").forEach((b) => b.classList.toggle("active", b === optBtn));
            if (layoutState.selectedSceneIndex === index) {
              syncCurrentSceneOverlay(scene, val, true);
            }
            notifyChange();
            closeSceneFramePopover();
          });
          ratioGrid.appendChild(optBtn);
        });
        pop.appendChild(ratioGrid);

        pop.style.position = "fixed";
        document.body.appendChild(pop);
        const btnRect = frameBtn.getBoundingClientRect();
        const popRect = pop.getBoundingClientRect();
        pop.style.left = `${Math.round(btnRect.left + btnRect.width / 2)}px`;
        pop.style.transform = "translateX(-50%)";
        const spaceBelow = window.innerHeight - btnRect.bottom;
        if (spaceBelow < popRect.height + 8) {
          pop.style.top = `${Math.round(btnRect.top)}px`;
          pop.style.transform = "translate(-50%, -100%)";
        } else {
          pop.style.top = `${Math.round(btnRect.bottom + 4)}px`;
        }
        setTimeout(() => {
          document.addEventListener("click", closeSceneFramePopover, { once: true });
          document.addEventListener("keydown", closeSceneFramePopover, { once: true });
        }, 0);
      });
      const frameCtrl = document.createElement("div");
      frameCtrl.className = "scene-frame-ctrl";
      frameCtrl.appendChild(frameBtn);
      frameCtrl.appendChild(frameChk);
      tdAspect.appendChild(frameCtrl);

      // 5. Scale Cell (Масштаб) — постраничное размещение на листе
      const tdScale = document.createElement("td");
      tdScale.className = "scene-scale-cell";
      const selScale = document.createElement("select");
      selScale.className = "table-select scene-scale-select";
      selScale.title = "Размещение картинки на странице (% от листа)";
      [60, 70, 80, 90, 100].forEach((pct) => {
        const opt = document.createElement("option");
        opt.value = String(pct);
        opt.textContent = `${pct}%`;
        selScale.appendChild(opt);
      });
      selScale.value = String(parseInt(scene.scale_pct, 10) || 100);
      selScale.addEventListener("focus", () => {
        layoutState.selectedSceneIndex = index;
        highlightActiveSceneRow(index);
        switchToSketchupScene(scene, index);
      });
      selScale.addEventListener("change", (e) => {
        const scale = parseInt(e.target.value, 10) || 100;
        scene.scale_pct = scale;
        updateBlockSlot("image_4_3", { scale_pct: scale });
        if (layoutState.selectedSceneIndex === index) {
          syncCurrentSceneOverlay(scene, null, true);
        }
        notifyChange();
      });
      selScale.addEventListener("click", (e) => e.stopPropagation());
      tdScale.appendChild(selScale);

      // 6. Align Cell (Выравнивание) — постраничное выравнивание эскиза (сетка 3×3)
      const tdAlign = document.createElement("td");
      tdAlign.className = "scene-align-cell";
      const alignBtn = document.createElement("button");
      alignBtn.type = "button";
      alignBtn.className = "scene-align-btn";
      const sceneAlignH = SCENE_ALIGN_H.includes(scene.align_h) ? scene.align_h : "center";
      const sceneAlignV = SCENE_ALIGN_V.includes(scene.align_v) ? scene.align_v : "center";
      alignBtn.textContent = alignGlyph(sceneAlignH, sceneAlignV);
      alignBtn.title = `Выравнивание эскиза: ${sceneAlignTitle(sceneAlignH, sceneAlignV)}`;
      alignBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const existing = document.getElementById("sceneAlignPopover");
        if (existing) {
          closeSceneAlignPopover();
          return;
        }
        const pop = document.createElement("div");
        pop.id = "sceneAlignPopover";
        pop.className = "scene-align-pop";
        pop.addEventListener("click", (ev) => ev.stopPropagation());
        [
          ["left", "top"], ["center", "top"], ["right", "top"],
          ["left", "center"], ["center", "center"], ["right", "center"],
          ["left", "bottom"], ["center", "bottom"], ["right", "bottom"]
        ].forEach(([h, v]) => {
          const optBtn = document.createElement("button");
          optBtn.type = "button";
          optBtn.className = "scene-align-opt" + (h === sceneAlignH && v === sceneAlignV ? " active" : "");
          optBtn.textContent = alignGlyph(h, v);
          optBtn.title = sceneAlignTitle(h, v);
          optBtn.addEventListener("click", (ev) => {
            ev.stopPropagation();
            scene.align_h = h;
            scene.align_v = v;
            alignBtn.textContent = alignGlyph(h, v);
            alignBtn.title = `Выравнивание эскиза: ${sceneAlignTitle(h, v)}`;
            closeSceneAlignPopover();
            notifyChange();
          });
          pop.appendChild(optBtn);
        });
        pop.style.position = "fixed";
        document.body.appendChild(pop);
        const btnRect = alignBtn.getBoundingClientRect();
        const popRect = pop.getBoundingClientRect();
        pop.style.left = `${Math.round(btnRect.left + btnRect.width / 2)}px`;
        pop.style.transform = "translateX(-50%)";
        const spaceBelow = window.innerHeight - btnRect.bottom;
        if (spaceBelow < popRect.height + 8) {
          pop.style.top = `${Math.round(btnRect.top)}px`;
          pop.style.transform = "translate(-50%, -100%)";
        } else {
          pop.style.top = `${Math.round(btnRect.bottom + 4)}px`;
        }
        setTimeout(() => {
          document.addEventListener("click", closeSceneAlignPopover, { once: true });
          document.addEventListener("keydown", closeSceneAlignPopover, { once: true });
        }, 0);
      });
      tdAlign.appendChild(alignBtn);

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
        opt.textContent = t.name; // в списке страниц — только имя шаблона
        if (t.description) opt.title = t.description; // описание — в подсказке при наведении
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
      // Подсказка на закрытом селекте — описание выбранного шаблона
      const selectedTpl = allTemplates.find((t) => t.key === scene.page_type) || allTemplates[0];
      if (selectedTpl && selectedTpl.description) {
        selType.title = selectedTpl.description;
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
      btnEditTpl.innerHTML = '<i class="modus-icons" style="font-size: 13px;">settings</i>';
      btnEditTpl.addEventListener("click", (e) => {
        e.stopPropagation();
        layoutState.selectedSceneIndex = index;
        selectTemplate(scene.page_type || (allTemplates[0] ? allTemplates[0].key : ""));
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
      tr.appendChild(tdScale);
      tr.appendChild(tdAlign);
      tr.appendChild(tdType);

      els.scenesTableBody.appendChild(tr);
    });

    updateLayoutUsageBadge();

    // Trigger thumbnail generation from SketchUp if not done yet
    if (!requestedSceneThumbnails && window.sketchup && typeof window.sketchup.getSceneThumbnails === "function") {
      requestSceneThumbnails();
    }
  }

  // Render Stadia Checkboxes
  let draggedStadiaIndex = null;

  // Пересчитывает статус проекта по последней отмеченной стадии (порядок стадий значим)
  function updateStadiaStatus() {
    const stadia = state.workflow && Array.isArray(state.workflow.stadia) ? state.workflow.stadia : [];
    const lastChecked = [...stadia].reverse().find((s) => s.status);
    if (!lastChecked) return;
    state.workflow = state.workflow || {};
    state.workflow.status = lastChecked.name;
    if (state.project_info) state.project_info.status = lastChecked.name;
    if (els.inputStatus) {
      const opts = Array.from(els.inputStatus.options).map((o) => o.value);
      if (opts.includes(lastChecked.name)) {
        els.inputStatus.value = lastChecked.name;
      }
    }
  }

  function renderStadia() {
    if (!els.stadiaCheckboxesContainer) return;
    els.stadiaCheckboxesContainer.innerHTML = "";

    const defaultStadia = [
      { name: "Предварительный проект", status: true },
      { name: "Правки проекта (история правок)", status: false },
      { name: "Выбраны материалы и фурнитура", status: false },
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
        updateStadiaStatus();
        notifyChange();
      });

      const span = document.createElement("span");
      span.className = "stadia-name";
      span.textContent = st.name || `Стадия ${idx + 1}`;

      // Кнопка удаления стадии (последнюю оставшуюся не удаляем)
      const btnDel = document.createElement("button");
      btnDel.type = "button";
      btnDel.className = "stadia-delete";
      btnDel.innerHTML = MODUS_CROSS_SVG;
      btnDel.title = "Удалить стадию";
      if (stadia.length <= 1) btnDel.style.display = "none";
      btnDel.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (state.workflow.stadia.length <= 1) return;
        state.workflow.stadia.splice(idx, 1);
        renderStadia();
        updateStadiaStatus();
        notifyChange();
      });

      // Drag and Drop переупорядочивание строк (как у таблицы сцен)
      label.addEventListener("mousedown", (e) => {
        label.setAttribute("draggable", e.target.closest("input, button") ? "false" : "true");
      });
      label.addEventListener("mouseup", () => {
        label.setAttribute("draggable", "true");
      });
      label.addEventListener("dragstart", (e) => {
        draggedStadiaIndex = idx;
        label.classList.add("dragging");
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", String(idx));
      });
      label.addEventListener("dragend", () => {
        draggedStadiaIndex = null;
        label.classList.remove("dragging");
        els.stadiaCheckboxesContainer.querySelectorAll(".stadia-checkbox-item").forEach((row) => {
          row.classList.remove("drag-over-top", "drag-over-bottom");
        });
      });
      label.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (draggedStadiaIndex === null || draggedStadiaIndex === idx) return;
        const rect = label.getBoundingClientRect();
        const isTop = e.clientY - rect.top < rect.height / 2;
        label.classList.toggle("drag-over-top", isTop);
        label.classList.toggle("drag-over-bottom", !isTop);
      });
      label.addEventListener("dragleave", () => {
        label.classList.remove("drag-over-top", "drag-over-bottom");
      });
      label.addEventListener("drop", (e) => {
        e.preventDefault();
        e.stopPropagation();
        label.classList.remove("drag-over-top", "drag-over-bottom");
        if (draggedStadiaIndex === null || draggedStadiaIndex === idx) return;

        const rect = label.getBoundingClientRect();
        let dropIndex = e.clientY - rect.top < rect.height / 2 ? idx : idx + 1;
        if (draggedStadiaIndex < dropIndex) dropIndex -= 1;

        if (dropIndex !== draggedStadiaIndex) {
          const item = state.workflow.stadia.splice(draggedStadiaIndex, 1)[0];
          state.workflow.stadia.splice(dropIndex, 0, item);
          renderStadia();
          updateStadiaStatus();
          notifyChange();
        }
      });

      label.appendChild(chk);
      label.appendChild(span);
      label.appendChild(btnDel);
      els.stadiaCheckboxesContainer.appendChild(label);
    });
  }

  // Render History Table
  // Render History Table: ui.history хранит { uid, item }, где item — тот же
  // объект state.history (прокси Vue пишет насквозь); рендер — HistoryTab.vue
  function renderHistoryTable() {
    ui.history = (state.history || []).map((item, index) => ({ uid: "h" + index + "-" + (item.data || ""), item }));
  }

  // Добавление правки (кнопка в HistoryTab.vue)
  function addHistoryEntry() {
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
  }

  // Удаление правки (кнопка в строке таблицы HistoryTab.vue)
  function removeHistoryEntry(index) {
    state.history.splice(index, 1);
    renderHistoryTable();
    notifyChange();
  }

  // Синхронизация трёх полей записи (edit/text/description) и поля «Последняя правка»
  function syncHistoryEdit(index, value) {
    const item = state.history[index];
    if (!item) return;
    item.edit = value;
    item.text = value;
    item.description = value;
    if (index === 0 && els.inputLastEdit) {
      els.inputLastEdit.value = value;
    }
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
    const rateVal = (els.inputRate ? els.inputRate.value : "").trim();

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
      company: compVal,
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
      rate: rateVal,
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
      rate:             rateVal,
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
      show_aspect_overlay: Boolean(state.pdf_settings && state.pdf_settings.show_aspect_overlay),
      overlay_border_color: state.pdf_settings?.overlay_border_color || "#FF0000",
      overlay_border_opacity: state.pdf_settings?.overlay_border_opacity !== undefined ? state.pdf_settings.overlay_border_opacity : 100,
      overlay_mask_color: state.pdf_settings?.overlay_mask_color || "#0F172A",
      overlay_mask_opacity: state.pdf_settings?.overlay_mask_opacity !== undefined ? state.pdf_settings.overlay_mask_opacity : 10,
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

    // Directories: кнопки «Добавить папку» и «Обновить» перенесены в
    // DirectoriesTab.vue — действия приходят через window.legacy
    // (addDirectory / refreshDirectories).

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

    // «Шаблон всем»: назначить шаблон из первой строки всем сценам сразу
    if (els.btnApplyTemplateAll) {
      els.btnApplyTemplateAll.addEventListener("click", () => {
        const tpl = (state.scenes || [])[0] && state.scenes[0].page_type;
        if (!tpl) return;
        state.scenes.forEach((s) => { s.page_type = tpl; });
        renderScenesTable();
        notifyChange();
      });
    }

    // Обновить эскизы сцен вручную: SketchUp перелистывает страницы и снимает свежие мини-превью
    if (els.btnRefreshThumbs) {
      els.btnRefreshThumbs.addEventListener("click", () => {
        if (sceneThumbnailsInFlight) return;
        sceneThumbsManualRequest = true;
        requestSceneThumbnails(true);
      });
    }

    // Добавление пользовательской стадии в конец списка (кнопка или Enter)
    const addStadiaFromInput = () => {
      if (!els.inputNewStadia) return;
      const name = els.inputNewStadia.value.trim();
      if (!name) return;
      state.workflow = state.workflow || {};
      if (!Array.isArray(state.workflow.stadia) || state.workflow.stadia.length === 0) {
        state.workflow.stadia = [];
      }
      state.workflow.stadia.push({ name, status: false });
      els.inputNewStadia.value = "";
      renderStadia();
      notifyChange();
    };
    if (els.btnAddStadia) els.btnAddStadia.addEventListener("click", addStadiaFromInput);
    if (els.inputNewStadia) {
      els.inputNewStadia.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          addStadiaFromInput();
        }
      });
    }

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

    // Водяные знаки сцены: независимая от фона галка, включается/выключается сразу
    // на всех страницах, эскизы в таблице перегенерируются с учётом нового состояния
    if (els.chkScenesWatermarks) {
      els.chkScenesWatermarks.addEventListener("change", (e) => {
        const wmOn = e.target.checked;
        (state.scenes || []).forEach((s) => { s.viewport_watermarks = wmOn; });
        requestSceneThumbnails(true);
        notifyChange();
      });
    }

    // «Кадр все»: массовое включение/выключение рамки кадра сразу на всех страницах
    if (els.chkScenesFrameAll) {
      els.chkScenesFrameAll.addEventListener("change", (e) => {
        const on = e.target.checked;
        (state.scenes || []).forEach((s) => { s.frame_overlay = on; });
        updateSceneTableFrameStates();
        callRuby("toggleAspectOverlay", JSON.stringify({ enabled: on, all: true }));
        notifyChange();
      });
    }

    // Add History Entry (edit_history.yaml)
    // Кнопка «Добавить правку» перенесена в HistoryTab.vue → window.legacy.addHistoryEntry

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

    // Dev Tools Update & Hot Reload listeners
    const btnDevUpdate = document.getElementById("btnUpdateFromDev");
    if (btnDevUpdate) {
      btnDevUpdate.addEventListener("click", () => {
        const devInput = document.getElementById("inputDevDir");
        const devPath = (devInput ? devInput.value : "").trim();
        const statusEl = document.getElementById("devUpdateStatus");
        if (statusEl) {
          statusEl.style.color = "var(--bs-primary)";
          statusEl.textContent = "Синхронизация файлов из dev-папки и перезагрузка...";
        }
        callRuby("updateFromDev", devPath);
      });
    }

    const btnDevReload = document.getElementById("btnHotReload");
    if (btnDevReload) {
      btnDevReload.addEventListener("click", () => {
        const statusEl = document.getElementById("devUpdateStatus");
        if (statusEl) {
          statusEl.style.color = "var(--bs-primary)";
          statusEl.textContent = "Перезагрузка плагина в памяти SketchUp...";
        }
        callRuby("hotReload");
      });
    }

    // Success Modal
    if (els.btnOpenPdfFolder) {
      els.btnOpenPdfFolder.addEventListener("click", () => {
        if (state.lastExportedPdf) {
          callRuby("openFolder", state.lastExportedPdf);
        }
      });
    }

    if (els.btnCloseSuccessModal) {
      els.btnCloseSuccessModal.addEventListener("click", () => {
        if (els.successModal) els.successModal.classList.add("hidden");
      });
    }

    if (els.successPdfPath) {
      els.successPdfPath.addEventListener("click", () => {
        const text = (els.successPdfPath.textContent || "").trim();
        if (text) {
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(() => {
              showNotification("Путь к PDF скопирован в буфер обмена", "success");
            }).catch(() => {
              showNotification(text, "info");
            });
          } else {
            showNotification("Файл: " + text, "info");
          }
        }
      });
    }

    document.addEventListener("keydown", (e) => {
      if (els.successModal && !els.successModal.classList.contains("hidden")) {
        if (e.key === "Escape" || e.key === "Enter") {
          els.successModal.classList.add("hidden");
        }
      }
      if (e.key === "Escape" && els.articulTypeModal && !els.articulTypeModal.classList.contains("hidden")) {
        closeArticulTypeModal();
      }
    });

    // Auto-save listeners for all dialog input fields across tabs
    const autoSaveInputIds = [
      "inputRoomName", "inputFurnitureName", "inputCustomer", "inputCustomerId",
      "inputCompany", "inputArticul", "inputTags",
      "inputProjectDescription", "inputAddress", "inputPhone", "inputEmail",
      "inputAuthor", "inputPrice", "inputStartDate", "inputEndDate",
      "inputTotalDuration", "inputRate", "inputStatus", "inputRevision", "inputVersion",
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
      if (data.plugin_version) {
        state.plugin_version = data.plugin_version;
        const vEl = document.getElementById("logoVersion");
        if (vEl) vEl.textContent = `v${data.plugin_version}`;
        const devBadge = document.getElementById("badgeDevVersion");
        if (devBadge) devBadge.textContent = `v${data.plugin_version}`;
        document.title = `DN1C Export PDF 2 v${data.plugin_version}`;
      }
      if (data.dev_dir) {
        state.dev_dir = data.dev_dir;
        const inputDev = document.getElementById("inputDevDir");
        if (inputDev && !inputDev.value) inputDev.value = data.dev_dir;
      }
      ensureCustomLayouts();
      // Список наборов шаблонов приходит в payload getData (state.template_sets)
      renderTemplateSetsList();
      // Если выбранный шаблон удалён (или список пуст) — выбираем первый доступный
      const tplKeys = Object.keys(state.pdf_settings?.custom_layouts || {});
      if (!tplKeys.includes(layoutState.currentTemplate)) {
        layoutState.currentTemplate = tplKeys[0] || "";
      }
      syncDirectoriesSpecifications();
      renderUI();
      // Если диалог уже открыт на вкладке «Страницы», актуализируем
      // список страниц и эскизы (повторное открытие диалога из меню)
      const scenesPane = document.getElementById("tab-scenes");
      if (scenesPane && scenesPane.classList.contains("active")) {
        refreshScenesFromModel();
      }
      // При открытии панели предлагаем создать артикул (если проект еще без артикула)
      setTimeout(maybeOfferArticulCreation, 300);
    },

    // Ruby прислал обновлённый список наборов шаблонов (после сохранения/удаления)
    onTemplateSetsUpdated: function (payload) {
      state.template_sets = (payload && payload.sets) || [];
      renderTemplateSetsList();
    },

    // Ruby загрузил набор шаблонов: custom_layouts заменен целиком — применяем
    // к состоянию, переключаем сцены отсутствующих шаблонов и перерисовываем UI
    onTemplateSetLoaded: function (payload) {
      const layouts = payload && payload.custom_layouts;
      if (!layouts || typeof layouts !== "object") return;

      if (!state.pdf_settings) state.pdf_settings = {};
      state.pdf_settings.custom_layouts = layouts;

      // Сцены шаблонов, отсутствующих в наборе, → первый доступный шаблон
      const keys = Object.keys(layouts);
      const fallbackKey = keys[0] || "";
      if (fallbackKey) {
        (state.scenes || []).forEach((s) => {
          if (!keys.includes(s.page_type)) {
            s.page_type = fallbackKey;
          }
        });
      }

      if (!keys.includes(layoutState.currentTemplate)) {
        layoutState.currentTemplate = fallbackKey;
      }

      syncTemplateDropdowns();
      renderScenesTable();
      if (fallbackKey) {
        selectTemplate(fallbackKey);
      } else {
        layoutState.currentTemplate = "";
        renderTemplateSettingsList(true);
        renderTemplatesList();
        updateLayoutUsageBadge();
      }
      notifyChange();
    },

    onDevUpdateResult: function (res) {
      const statusEl = document.getElementById("devUpdateStatus");
      if (res && res.success) {
        const msg = res.same_dir
          ? "Плагин работает напрямую из рабочей dev-папки. Перезагрузка выполнена!"
          : (res.files_copied !== undefined
              ? `Успешно обновлено из dev-папки (${res.files_copied} файлов скопировано). Плагин перезагружен!`
              : "Плагин успешно перезагружен!");
        if (statusEl) {
          statusEl.style.color = "var(--bs-success)";
          statusEl.textContent = `✅ ${msg} [${res.updated_at || res.reloaded_at || ""}]`;
          const warnings = (res.warnings || []).filter(Boolean);
          if (warnings.length) {
            const warnEl = document.createElement("div");
            warnEl.style.color = "var(--bs-warning)";
            warnEl.textContent = `⚠ Пропущено файлов: ${warnings.length} (загруженные DLL обновятся после перезапуска SketchUp) — ${warnings.join("; ")}`;
            statusEl.appendChild(warnEl);
          }
        }
        showNotification(msg, "success");
      } else {
        const errMsg = res ? res.error : "Неизвестная ошибка";
        if (statusEl) {
          statusEl.style.color = "var(--bs-danger)";
          statusEl.textContent = `❌ Ошибка: ${errMsg}`;
        }
        showNotification(`Ошибка обновления: ${errMsg}`, "error");
      }
    },

    showNotification: showNotification,

    // Папка проекта <Артикул> создана рядом с рабочим файлом (ответ Ruby-колбэка createProjectFolder)
    onProjectFolderCreated: function (folderPath, yamlSaved) {
      if (!folderPath) return;
      showNotification(
        (yamlSaved ? `Папка проекта создана: ${folderPath} (project.yaml записан)` : `Папка проекта создана: ${folderPath}`) +
          " — сохраните модель (Ctrl+S), чтобы артикул остался в файле .skp",
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
    },

    // Нативная смена активной страницы в SketchUp (вкладки сцен): панель следует
    // за моделью — выделение в таблице сцен переезжает на новую страницу.
    // Вызывается из Ruby (notify_active_scene) только когда страница совпадает
    // со сценой проекта; сырые страницы SketchUp выделение не меняют.
    onActiveSceneChanged: function (index) {
      const scenes = state.scenes || [];
      if (typeof index !== "number" || index < 0 || index >= scenes.length) return;
      if (layoutState.selectedSceneIndex === index) return;
      layoutState.selectedSceneIndex = index;
      highlightActiveSceneRow(index);
    },

    updateAspectInfo: function (info) {
      // Параметры кадра отображаются в меню кадра таблицы страниц —
      // отдельных бейджей и подписей в диалоге больше нет
    },

    setAspectRatio: function (ratio) {
      const VALID_ASPECT_RATIOS = ["page", "16:9", "4:3", "3:2", "5:4", "1:1", "4:5", "custom"];
      if (!VALID_ASPECT_RATIOS.includes(ratio)) {
        ratio = "4:3";
      }
      const idx = layoutState.selectedSceneIndex || 0;
      const scene = (state.scenes || [])[idx];
      if (scene) {
        scene.aspect_ratio = ratio;
        updateSceneTableAspectCell(idx, ratio);
      }
      updateBlockSlot("image_4_3", { aspect_ratio: ratio });
      if (!state.pdf_settings) state.pdf_settings = {};
      state.pdf_settings.image_aspect_ratio = ratio;
      if (els.selectImageAspect) els.selectImageAspect.value = ratio;
      syncCurrentTemplateOverlay(ratio, true);
      notifyChange();
    },

    onSceneThumbnailsLoaded: function (thumbs) {
      sceneThumbnailsInFlight = false;
      const gotThumbs = thumbs && typeof thumbs === "object" && Object.keys(thumbs).length > 0;
      if (thumbs && typeof thumbs === "object") {
        Object.assign(sceneThumbnails, thumbs);
        updateSceneTablePreviews();
      }
      sceneThumbnailsSig = sceneThumbnailsSignature();
      if (sceneThumbsManualRequest) {
        sceneThumbsManualRequest = false;
        if (gotThumbs) {
          showNotification("Эскизы сцен обновлены", "success");
        } else {
          showNotification("Не удалось получить эскизы сцен", "error");
        }
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
      // Эскизы перегенерируются только если набор сцен изменился
      // (состав/имена/порядок страниц, флаг «Фон») — иначе SketchUp
      // зря перелистывает страницы; вручную — кнопка «Обновить эскизы»
      requestSceneThumbnails(false);
    },

    syncCurrentTemplateOverlay: syncCurrentTemplateOverlay
  };

  // Мост для Vue-компонентов на время миграции: они вызывают бизнес-логику отсюда
  window.legacy = {
    openParamModal,
    closeParamModal,
    confirmParamModal,
    updateParamModalPreview,
    addDirectory,
    refreshDirectories,
    commitDirectories,
    addHistoryEntry,
    removeHistoryEntry,
    syncHistoryEdit,
    notifyChange,
    callRuby
  };

  // Initialization. Модуль грузится динамическим импортом уже после монтирования
  // Vue, поэтому DOMContentLoaded мог уже пройти — инициализируемся сразу.
  function init() {
    setupTabs();
    setupEventListeners();
    setupLayoutEditor();
    setupSplitResizer();
    setupScrollWheelHandlers();

    // Request initial data from SketchUp
    callRuby("getData");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
