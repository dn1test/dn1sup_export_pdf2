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
    stadiaCheckboxesContainer: null, // рендер стадий — ProjectTab.vue
    inputNewStadia: null,
    btnAddStadia: null,
    inputLastEdit: document.getElementById("inputLastEdit"),

    // Tab Directories
    // Вкладка «Папки» рендерится Vue-компонентом DirectoriesTab.vue

    // Tab Settings
    // Вкладка «Отправка»: список адресатов рендерит Vue-компонент SendTab.vue

    // Tab 2 Elements: Scenes & Layout Split View
    layoutTplUsageBadge: document.getElementById("layoutTplUsageBadge"),
    // Таблица сцен рендерится Vue-компонентом ScenesTab.vue
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
    currentTemplateTitle: document.getElementById("currentTemplateTitle"),
    btnRenameCurrentTemplate: document.getElementById("btnRenameCurrentTemplate"),
    btnDeleteCurrentTemplate: document.getElementById("btnDeleteCurrentTemplate"),
    inputNewTemplateName: document.getElementById("inputNewTemplateName"),
    inputNewTemplateDescription: document.getElementById("inputNewTemplateDescription"),
    selectNewTemplateBase: document.getElementById("selectNewTemplateBase"),
    inputRenameTemplateName: document.getElementById("inputRenameTemplateName"),
    inputRenameTemplateDescription: document.getElementById("inputRenameTemplateDescription"),
    inputTemplateSetName: document.getElementById("inputTemplateSetName"),
    templateSettingsPanel: document.getElementById("templateSettingsPanel"),
    // Редактор параметров шаблона рендерится TemplateSettingsEditor.vue
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
                antialias: true,
                custom_layouts: {
                  cover: { name: "Титульный лист (Cover)", description: "Обложка проекта" },
                  explain: { name: "Содержание и материалы (Explain)", description: "Пояснительная записка" },
                  visual: { name: "Перспективный вид (Visual)", description: "Визуализация" },
                  general: { name: "План расстановки (General)", description: "Техническая схема" }
                }
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
    const templates = getAllTemplates();
    const currentKey = layoutState.currentTemplate || (templates[0] ? templates[0].key : "");
    const scenes = state.scenes || [];

    ui.templates = templates.map((tpl) => {
      const matchingScenes = scenes.filter((s) => s.page_type === tpl.key);
      const usageText = matchingScenes.length > 0
        ? `${matchingScenes.length} ${matchingScenes.length === 1 ? "сцена" : (matchingScenes.length < 5 ? "сцены" : "сцен")}`
        : "не используется";
      // Второй строкой — описание шаблона (мелче); без описания — использование
      const subText = tpl.description || usageText;
      return { key: tpl.key, name: tpl.name, description: tpl.description || "", sub: subText, active: tpl.key === currentKey };
    });
  }

  let templatePendingDelete = null;
  let templatePendingRename = null;

  function selectTemplate(tplKey) {
    flushAutoSave();
    layoutState.currentTemplate = tplKey;
    ui.currentTemplate = tplKey;
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
    ui.tplModals.deleteTemplate = { key: tplKey, name: tplDef.name };
  }

  function closeDeleteTemplateModal() {
    templatePendingDelete = null;
    ui.tplModals.deleteTemplate = null;
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
      ui.currentTemplate = layoutState.currentTemplate;
      selectTemplate(fallbackKey);
    } else {
      layoutState.currentTemplate = "";
      ui.currentTemplate = layoutState.currentTemplate;
      renderTemplateSettingsList(true);
      updateLayoutUsageBadge();
    }
    notifyChange();
    showNotification(`Шаблон «${tplDef.name}» удален${reassignedCount > 0 ? ` (сцен переключено: ${reassignedCount})` : ""}`, "info");
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
    const sets = state.template_sets || [];
    ui.templateSets = sets.map((set) => {
      const count = set.templates_count || 0;
      const dateStr = formatTemplateSetDate(set.saved_at);
      return {
        name: set.name,
        sub: `${count} ${templateSetsCountWord(count)}${dateStr ? ` · ${dateStr}` : ""}`,
      };
    });
  }

  function openConfirmTemplateSetModal(action) {
    templateSetPendingAction = action;
    const name = action ? action.name : "";
    const isDelete = !!action && action.type === "delete";
    const isOverwrite = !!action && action.type === "overwrite";
    const isRefresh = !!action && action.type === "refresh";
    ui.tplModals.confirmSet = {
      type: action ? action.type : "load",
      name: name,
      title: isDelete
        ? "Удаление набора шаблонов"
        : (isOverwrite ? "Перезапись набора шаблонов"
            : (isRefresh ? "Обновление набора шаблонов" : "Загрузка набора шаблонов")),
      msg: isDelete
        ? `Вы действительно хотите удалить набор «${name}»?`
        : (isOverwrite
            ? `Набор «${name}» уже существует. Перезаписать его текущим списком шаблонов?`
            : (isRefresh
                ? `Обновить набор «${name}» текущим списком шаблонов? Содержимое набора будет перезаписано.`
                : `Вы действительно хотите загрузить набор «${name}»?`)),
      danger: isDelete,
    };
  }

  function closeConfirmTemplateSetModal() {
    templateSetPendingAction = null;
    ui.tplModals.confirmSet = null;
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
    ui.tplModals.saveSet = { name: "" };
  }

  function closeSaveTemplateSetModal() {
    ui.tplModals.saveSet = null;
  }

  function confirmSaveTemplateSet(rawName) {
    const name = String(rawName || "").trim();
    if (!name) {
      showNotification("Укажите название набора", "warning");
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
    ui.tplModals.renameTemplate = { key: tplKey, name: tplDef.name, description: tplDef.description || "" };
  }

  function closeRenameTemplateModal() {
    templatePendingRename = null;
    ui.tplModals.renameTemplate = null;
  }

  function confirmRenameTemplate(rawName, rawDesc) {
    const tplKey = templatePendingRename;
    if (!tplKey) {
      closeRenameTemplateModal();
      return;
    }
    const newName = String(rawName || "").trim();
    if (!newName) {
      showNotification("Название шаблона не может быть пустым", "warning");
      return;
    }
    const newDesc = String(rawDesc || "").trim();

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

  // Модалка создания шаблона (TemplatesSidebar.vue / NewTemplateModal.vue)
  function openNewTemplateModal() {
    ensureCustomLayouts();
    ui.tplModals.newTemplate = {
      name: "",
      description: "",
      base: "empty",
      bases: [{ key: "empty", name: "Пустой шаблон — базовый видовой экран" }]
        .concat(getAllTemplates().map((t) => ({ key: t.key, name: t.name }))),
    };
  }

  function confirmNewTemplate(rawName, baseType, rawDescription) {
    const name = String(rawName || "").trim();
    const description = String(rawDescription || "").trim();
    if (!name) {
      showNotification("Введите название шаблона", "warning");
      return;
    }
    createCustomTemplate(name, baseType || "empty", description);
    ui.tplModals.newTemplate = null;
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
  ensureCustomLayouts();
  syncDirectoriesSpecifications();

  const tplKey = layoutState.currentTemplate || (getAllTemplates()[0] ? getAllTemplates()[0].key : "");
  const tplDefObj = getTemplateDef(tplKey);

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

  // Рендер списка — Vue-компонент TemplateSettingsEditor.vue: снимок параметров
  // с вычисленными подписями; мутации идут через tplEditor*-мосты ниже
  const tplLine = getTemplateLineSettings(tplKey);
  const decorateChild = (c) => {
    const cPrev = paramPreviewValue(c.source);
    const cLabel = c.show_label ? effectiveParamLabel(c.source, c.label) : "";
    return Object.assign({}, c, {
      _label: paramSourceLabel(c.source),
      _shownLabel: cLabel,
      _preview: cPrev.replace(/\n+/g, " ⏎ ")
    });
  };
  const decorate = (p) => {
    const preview = paramPreviewValue(p.source);
    const shownLabel = p.show_label ? effectiveParamLabel(p.source, p.label) : "";
    return Object.assign({}, p, {
      _label: paramSourceLabel(p.source),
      _shownLabel: shownLabel,
      _preview: preview.replace(/\n+/g, " ⏎ "),
      _zone: paramZoneLabel(p),
      _children: Array.isArray(p.params) ? p.params.map(decorateChild) : []
    });
  };

  ui.tplEditor = {
    tplKey: tplKey,
    lineGap: tplLine.line_gap,
    lineEnabled: tplLine.line_enabled,
    params: getTemplateParams(tplKey).map(decorate)
  };

  syncCurrentTemplateOverlay(null, isUserAction);
}

  // -------------------------------------------------------------
  // Мутаторы редактора параметров (TemplateSettingsEditor.vue → legacy):
  // изменение уходит в state.template_params, затем список ре-синхронизируется
  // -------------------------------------------------------------
  function tplEditorSetVisible(id, checked) {
    const tplKey = ui.tplEditor.tplKey;
    setTemplateParams(getTemplateParams(tplKey).map((p) => (p.id === id ? Object.assign({}, p, { visible: checked }) : p)), tplKey);
    // Класс disabled-block в строке реактивно зависит от ui-копии — обновляем её
    const entry = ui.tplEditor.params.find((p) => p.id === id);
    if (entry) entry.visible = checked;
    notifyChange();
  }

  function tplEditorDeleteRow(id) {
    const tplKey = ui.tplEditor.tplKey;
    setTemplateParams(getTemplateParams(tplKey).filter((p) => p.id !== id), tplKey);
    renderTemplateSettingsList();
    notifyChange();
  }

  function tplEditorMove(id, delta) {
    const tplKey = ui.tplEditor.tplKey;
    const params = getTemplateParams(tplKey);
    const idx = params.findIndex((p) => p.id === id);
    const target = idx + delta;
    if (idx < 0 || target < 0 || target >= params.length) return;
    const swapped = [...params];
    [swapped[idx], swapped[target]] = [swapped[target], swapped[idx]];
    setTemplateParams(swapped, tplKey);
    renderTemplateSettingsList();
    notifyChange();
  }

  // updates применяются к строке; rerender нужен, когда меняются вычисляемые
  // подписи (show_label) — цвет/шрифт/размер обновляются без перерисовки
  function tplEditorUpdate(id, updates, rerender) {
    const tplKey = ui.tplEditor.tplKey;
    setTemplateParams(getTemplateParams(tplKey).map((p) => (p.id === id ? Object.assign({}, p, updates) : p)), tplKey);
    if (rerender) renderTemplateSettingsList();
    notifyChange();
  }

  function tplEditorSetLineEnabled(checked) {
    setTemplateLineSettings(ui.tplEditor.tplKey, { line_enabled: checked });
  }

  function tplEditorSetLineGap(rawGap) {
    const g = parseFloat(rawGap);
    if (!isNaN(g) && g >= 0) setTemplateLineSettings(ui.tplEditor.tplKey, { line_gap: g });
  }

  function tplEditorCreateGroup() {
    createParamGroup(ui.tplEditor.tplKey);
  }

  function tplEditorChildOut(groupId, childId) {
    const tplKey = ui.tplEditor.tplKey;
    const params = getTemplateParams(tplKey);
    const group = params.find((p) => p.id === groupId && p.group);
    if (!group || !Array.isArray(group.params)) return;
    const cIdx = group.params.findIndex((c) => c.id === childId);
    if (cIdx < 0) return;
    const [child] = group.params.splice(cIdx, 1);
    params.push(child);
    setTemplateParams(params, tplKey);
    renderTemplateSettingsList();
    notifyChange();
  }

  function tplEditorChildShowLabel(groupId, childId, checked) {
    const tplKey = ui.tplEditor.tplKey;
    const params = getTemplateParams(tplKey);
    const group = params.find((p) => p.group && Array.isArray(p.params) && p.params.some((c) => c.id === childId));
    if (!group) return;
    group.params = group.params.map((c) => (c.id === childId ? Object.assign({}, c, { show_label: checked }) : c));
    setTemplateParams(params, tplKey);
    renderTemplateSettingsList();
    notifyChange();
  }

  // Drop в редакторе: op = { dragId, fromGroup, kind: 'row'|'group'|'child',
  // targetId, before, toGroup }. Порядок в списке = порядок зон на листе.
  function tplEditorDrop(op) {
    const tplKey = ui.tplEditor.tplKey;
    const findGroup = (params, gid) => params.find((p) => p.id === gid && p.group);
    const params = getTemplateParams(tplKey);
    const dragId = op.dragId;
    const fromGroup = op.fromGroup;

    if (op.kind === "row") {
      if (fromGroup === null) {
        const fromIdx = params.findIndex((p) => p.id === dragId);
        if (fromIdx < 0) return;
        const [moved] = params.splice(fromIdx, 1);
        const toIdx = params.findIndex((p) => p.id === op.targetId);
        if (toIdx < 0) params.push(moved);
        else params.splice(op.before ? toIdx : toIdx + 1, 0, moved);
      } else {
        const src = findGroup(params, fromGroup);
        const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId);
        if (cIdx < 0) return;
        const [moved] = src.params.splice(cIdx, 1);
        const toIdx = params.findIndex((p) => p.id === op.targetId);
        if (toIdx < 0) params.push(moved);
        else params.splice(op.before ? toIdx : toIdx + 1, 0, moved);
      }
    } else if (op.kind === "group") {
      // бросок на список детей блока — параметр встаёт в конец строки блока
      let moved = null;
      if (fromGroup === null) {
        const idx = params.findIndex((p) => p.id === dragId);
        if (idx < 0) return;
        [moved] = params.splice(idx, 1);
      } else {
        const src = findGroup(params, fromGroup);
        const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId);
        if (cIdx < 0) return;
        [moved] = src.params.splice(cIdx, 1);
      }
      const dst = findGroup(params, op.targetId);
      if (!dst) {
        params.push(moved);
      } else {
        (dst.params = Array.isArray(dst.params) ? dst.params : []).push(moved);
      }
    } else if (op.kind === "child") {
      // бросок к конкретному ребенку: реордер внутри блока либо перенос между блоками
      const src = findGroup(params, fromGroup);
      const cIdx = (src && src.params ? src.params : []).findIndex((c) => c.id === dragId);
      if (cIdx < 0) return;
      const [moved] = src.params.splice(cIdx, 1);
      const dst = findGroup(params, op.toGroup);
      if (!dst) {
        const toIdx = params.findIndex((p) => p.id === op.targetId);
        if (toIdx < 0) params.push(moved);
        else params.splice(op.before ? toIdx : toIdx + 1, 0, moved);
      } else {
        const children = dst.params;
        const toIdx = children.findIndex((c) => c.id === op.targetId);
        if (toIdx < 0) children.push(moved);
        else children.splice(op.before ? toIdx : toIdx + 1, 0, moved);
      }
    }

    setTemplateParams(params, tplKey);
    renderTemplateSettingsList();
    notifyChange();
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

    // Модалки шаблонов (создание/удаление/переименование/наборы) перенесены в
    // Vue-компоненты; действия приходят через window.legacy. Кнопки «Удалить»/
    // «Переименовать» в шапке панели открывают те же модалки через store.
    if (els.btnDeleteCurrentTemplate) {
      els.btnDeleteCurrentTemplate.addEventListener("click", () => {
        openDeleteTemplateModal(layoutState.currentTemplate);
      });
    }

    if (els.btnRenameCurrentTemplate) {
      els.btnRenameCurrentTemplate.addEventListener("click", () => {
        openRenameTemplateModal(layoutState.currentTemplate);
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

  // Render API Targets (api_targets from project_config.yaml / settings):
  // рендер — SendTab.vue, здесь только синхронизация store
  function renderApiTargets() {
    if (!Array.isArray(state.api_targets)) {
      state.api_targets = [];
    }
    ui.apiTargets = state.api_targets.slice();
  }

  // Кнопка «+ Добавить URL» (SendTab.vue)
  function addApiTarget() {
    if (!Array.isArray(state.api_targets)) state.api_targets = [];
    state.api_targets.push("");
    renderApiTargets();
    notifyChange();
  }

  // Commit изменённого списка из SendTab.vue (ввод, удаление)
  function commitApiTargets(list) {
    state.api_targets = list;
    notifyChange();
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

  // Выделение строки сцены: layoutState — источник для legacy, ui — для Vue-классов
  function highlightActiveSceneRow(index) {
    layoutState.selectedSceneIndex = index;
    ui.selectedSceneIndex = index;
  }

  // Выравнивание (глифы/подписи) и попапы кадра перенесены в ScenesTab.vue;
  // мини-превью страницы рендерится декларативно из ui.sceneThumbnails.

  // Render Scenes Table: источник — state.scenes, рендер — Vue-компонент
  // ScenesTab.vue (ui.scenes, write-through). Здесь только синхронизация,
  // галки тулбара и запрос эскизов.
  function renderScenesTable() {
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

    const oldEntries = ui.scenes;
    ui.scenes = scenes.map((item, idx) => {
      const uid = "sc" + idx + "-" + (item.name || "") + "-" + (item.original_name || "");
      const prev = oldEntries[idx];
      return prev && prev.uid === uid ? prev : { uid, item };
    });

    // Свежий список шаблонов для селекта «Шаблон» (перестраивается при каждом
    // рендере таблицы — как в оригинале)
    ui.templateOptions = getAllTemplates().map((t) => ({ key: t.key, name: t.name, description: t.description || "" }));

    updateLayoutUsageBadge();

    // Trigger thumbnail generation from SketchUp if not done yet
    if (!requestedSceneThumbnails && window.sketchup && typeof window.sketchup.getSceneThumbnails === "function") {
      requestSceneThumbnails();
    }
  }

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

  // Render Stadia: ui.stadia хранит { uid, item } (write-through в
  // state.workflow.stadia), рендер — ProjectTab.vue
  function renderStadia() {
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

    ui.stadia = stadia.map((item, idx) => ({ uid: "st" + idx + "-" + (item.name || ""), item }));
  }

  // Мосты для ProjectTab.vue: мутации стадий из Vue-списка
  function stadiaChanged() {
    updateStadiaStatus();
    notifyChange();
  }

  function removeStadia(index) {
    if (!state.workflow || !Array.isArray(state.workflow.stadia)) return;
    if (state.workflow.stadia.length <= 1) return;
    state.workflow.stadia.splice(index, 1);
    renderStadia();
    updateStadiaStatus();
    notifyChange();
  }

  function commitStadia(from, to) {
    if (!state.workflow || !Array.isArray(state.workflow.stadia)) return;
    const item = state.workflow.stadia.splice(from, 1)[0];
    state.workflow.stadia.splice(to, 0, item);
    updateStadiaStatus();
    notifyChange();
  }

  function addStadia(name) {
    name = String(name || "").trim();
    if (!name) return;
    state.workflow = state.workflow || {};
    if (!Array.isArray(state.workflow.stadia) || state.workflow.stadia.length === 0) {
      state.workflow.stadia = [];
    }
    state.workflow.stadia.push({ name, status: false });
    renderStadia();
    notifyChange();
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

    // Синхронизация адресатов API: актуальные значения пишет SendTab.vue в state
    if (Array.isArray(state.api_targets)) {
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
    // Кнопка «+ Добавить URL» перенесена в SendTab.vue → window.legacy.addApiTarget

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
    // Добавление стадий перенесено в ProjectTab.vue → window.legacy.addStadia

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
        ui.currentTemplate = layoutState.currentTemplate;
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
      ui.currentTemplate = layoutState.currentTemplate;
      }

      syncTemplateDropdowns();
      renderScenesTable();
      if (fallbackKey) {
        selectTemplate(fallbackKey);
      } else {
        layoutState.currentTemplate = "";
      ui.currentTemplate = layoutState.currentTemplate;
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
        ui.sceneThumbnails = Object.assign({}, sceneThumbnails);
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
          highlightActiveSceneRow(Math.max(0, scenes.length - 1));
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

  // -------------------------------------------------------------
  // Мосты для ScenesTab.vue: действия строк таблицы страниц
  // -------------------------------------------------------------
  // Клик/фокус по строке: выделение, (опционально) выбор шаблона, сцена в SketchUp
  function focusScene(index, withTemplate) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    highlightActiveSceneRow(index);
    if (withTemplate !== false) {
      selectTemplate(scene.page_type || "cover");
    }
    updateLayoutUsageBadge();
    switchToSketchupScene(scene, index);
  }

  // Галка «Вкл» в строке
  function sceneEnabledChanged() {
    updateSceneBadge();
    renderLayoutCanvas();
    updateLayoutUsageBadge();
    notifyChange();
  }

  // Ввод названия/описания: живое обновление WYSIWYG-канвы
  function sceneTextChanged() {
    renderLayoutCanvas();
  }

  // Фиксация названия/описания (change): trim + пересчёт списков
  function sceneNameCommitted(index) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    scene.name = String(scene.name || "").trim();
    ui.scenes[index].item.name = scene.name;
    renderTemplateSettingsList();
    updateLayoutUsageBadge();
    notifyChange();
  }

  function sceneDescCommitted(index) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    scene.description = String(scene.description || "").trim();
    ui.scenes[index].item.description = scene.description;
    renderTemplateSettingsList();
    notifyChange();
  }

  // Галка рамки кадра в строке
  function sceneFrameToggled(index, on) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    highlightActiveSceneRow(index);
    switchToSketchupScene(scene, index);
    callRuby("toggleAspectOverlay", JSON.stringify({ enabled: on, scene_index: index }));
    if (on && layoutState.selectedSceneIndex === index) {
      syncCurrentSceneOverlay(scene, null, true);
    }
    notifyChange();
  }

  // Выбор пропорции в попапе кадра (scene.aspect_ratio уже записан Vue)
  function sceneRatioPicked(index, val) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    if (layoutState.selectedSceneIndex === index) {
      syncCurrentSceneOverlay(scene, val, true);
    }
    notifyChange();
  }

  // Смена масштаба (scene.scale_pct уже записан Vue)
  function sceneScaleChanged(index, scale) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    updateBlockSlot("image_4_3", { scale_pct: scale });
    if (layoutState.selectedSceneIndex === index) {
      syncCurrentSceneOverlay(scene, null, true);
    }
    notifyChange();
  }

  // Смена шаблона страницы в строке
  function scenePageTypeChanged(index, val) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    highlightActiveSceneRow(index);
    updateSceneBadge();
    selectTemplate(val);
    updateLayoutUsageBadge();
    switchToSketchupScene(scene, index);
    notifyChange();
  }

  // Кнопка «к шаблону» в строке: перейти к настройке шаблона страницы
  function gotoTemplateEditor(index) {
    const scene = (state.scenes || [])[index];
    if (!scene) return;
    highlightActiveSceneRow(index);
    const allTemplates = getAllTemplates();
    selectTemplate(scene.page_type || (allTemplates[0] ? allTemplates[0].key : ""));
    switchToSketchupScene(scene, index);
    switchToTab("tab-templates");
  }

  // Drop переупорядочивания строк (ui.scenes уже переставлен Vue)
  function commitScenesReorder(from, to) {
    const item = state.scenes.splice(from, 1)[0];
    state.scenes.splice(to, 0, item);
    state.scenes.forEach((s, idx) => (s.order = idx));
    updateSceneBadge();
    updateLayoutUsageBadge();
    const tplTab = document.getElementById("tab-templates");
    if (tplTab && tplTab.classList.contains("active")) {
      renderLayoutCanvas();
    }
    notifyChange();
  }

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
    addApiTarget,
    commitApiTargets,
    stadiaChanged,
    removeStadia,
    commitStadia,
    addStadia,
    focusScene,
    selectTemplate,
    tplEditorSetVisible,
    tplEditorDeleteRow,
    tplEditorMove,
    tplEditorUpdate,
    tplEditorSetLineEnabled,
    tplEditorSetLineGap,
    tplEditorCreateGroup,
    tplEditorChildOut,
    tplEditorChildShowLabel,
    tplEditorDrop,
    openNewTemplateModal,
    confirmNewTemplate,
    openRenameTemplateModal,
    closeRenameTemplateModal,
    confirmRenameTemplate,
    openDeleteTemplateModal,
    closeDeleteTemplateModal,
    confirmDeleteTemplate,
    openSaveTemplateSetModal,
    closeSaveTemplateSetModal,
    confirmSaveTemplateSet,
    openConfirmTemplateSetModal,
    closeConfirmTemplateSetModal,
    confirmTemplateSetAction,
    sceneEnabledChanged,
    sceneTextChanged,
    sceneNameCommitted,
    sceneDescCommitted,
    sceneFrameToggled,
    sceneRatioPicked,
    sceneScaleChanged,
    scenePageTypeChanged,
    gotoTemplateEditor,
    commitScenesReorder,
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
