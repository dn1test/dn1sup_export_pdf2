// Смоук-проверка динамического каталога параметров (app.js) вне SketchUp
"use strict";
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "dn1c_export_pdf2", "dialog", "html", "app.js"), "utf8");

// Вырезаем тело IIFE
const body = src.substring(src.indexOf("(function ()") + "(function ()".length, src.lastIndexOf("})();"));

// Из всего тела берём только участок каталога (от tval до deep clone) — без DOM-зависимостей
const catSrc = body.substring(body.indexOf("const tval"), body.indexOf("// Deep clone utility"));

const mocks = `
const state = { project_info: {}, pdf_settings: {}, scenes: [], directories: [], history: [] };
const layoutState = { currentTemplate: "cover", selectedSceneIndex: undefined };
`;

const harness = mocks + catSrc + `
  const info = { articul: "CF#1", furniture_name: "Шкаф", room_name: "Гостиная", address: "", phone: "+7 999", materials: "МДФ", price: "100000", version: "2", revision: "3" };
  const wf = { history_edit: [["2026-09-01 10:00", "Правка"]], stadia: [{ name: "РД", status: true }], date_order: "22.09.2026" };

  let bad = 0;
  const check = (name, ok) => { console.log((ok ? "PASS" : "FAIL") + " " + name); if (!ok) bad++; };

  const cat = buildParamCatalog(info, wf);
  const keys = cat.map((e) => e.key);

  check("артикул в списке", keys.includes("articul"));
  check("пустой address скрыт", !keys.includes("address"));
  check("пустой email скрыт", !keys.includes("customer_email"));
  check("заполненный телефон есть", keys.includes("customer_phone"));
  check("цена есть", keys.includes("workflow_price"));
  check("версия доступна всегда", keys.includes("workflow_version"));
  check("содержание доступно всегда", keys.includes("toc_pages"));
  check("page_total в каталоге", keys.includes("footer_page_total"));
  check("описание проекта скрыто (пусто)", !keys.includes("project_desc"));

  const headerKeys = cat.filter((e) => !e.footerOnly).map((e) => e.key);
  check("шапка/середина исключают footer_page_total", !headerKeys.includes("footer_page_total"));

  state.directories = [{ path: "C:/x", title: "Материалы", description: "ЛДСП" }];
  const cat2 = buildParamCatalog(info, wf);
  check("dir_desc_0 появляется для папки с описанием", cat2.some((e) => e.key === "dir_desc_0"));
  state.directories = [{ path: "C:/x", title: "Материалы", description: "" }];
  check("dir_desc_0 скрыт для папки без описания", !buildParamCatalog(info, wf).some((e) => e.key === "dir_desc_0"));

  state.directories = [{ path: "C:/x", title: "Материалы", description: "ЛДСП" }];
  const d0 = getInfoLineDef("dir_desc_0");
  check("getInfoLineDef(dir_desc_0).getVal = описание", d0 && d0.getVal(info, wf) === "ЛДСП");
  const cp = getInfoLineDef("customer_phone");
  check("getInfoLineDef возвращает реальное значение", cp && cp.getVal(info, wf) === "+7 999");
  const emptyAddr = getInfoLineDef("address");
  check("пустое поле даёт пустую строку превью", emptyAddr && emptyAddr.getVal({ address: "" }, {}) === "");

  process.exit(bad === 0 ? 0 : 1);
`;

new Function(harness)();
