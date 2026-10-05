// Офлайн-проверка орфографии для полей ввода.
// Встроенный браузер SketchUp (CEF) не включает собственный spellcheck, поэтому
// атрибут spellcheck в нём ничего не делает: словари Hunspell (nspell) для RU
// и EN вшиты в бандл и проверяются собственным кодом (см. overlay.js).
import nspell from 'nspell'
// Относительные пути в node_modules: exports-карта dictionary-* разрешает
// только корневой index.js, который читает файлы через fs и в браузере не работает
import ruAff from '../../node_modules/dictionary-ru/index.aff?raw'
import ruDic from '../../node_modules/dictionary-ru/index.dic?raw'
import enAff from '../../node_modules/dictionary-en/index.aff?raw'
import enDic from '../../node_modules/dictionary-en/index.dic?raw'

// Слово: кириллица или латиница, внутри допустимы дефис и апостроф
const WORD_RE = /[A-Za-zА-ЯЁа-яё]+(?:['’-][A-Za-zА-ЯЁа-яё]+)*/g
const HAS_CYR = /[а-яё]/i
const HAS_LAT = /[a-z]/i
const USER_WORDS_KEY = 'dn1sup_spell_user_words'

let spellerRu = null
let spellerEn = null
const correctness = new Map()

let userWords = (() => {
  try { return new Set(JSON.parse(localStorage.getItem(USER_WORDS_KEY) || '[]')) }
  catch { return new Set() }
})()

function saveUserWords() {
  try { localStorage.setItem(USER_WORDS_KEY, JSON.stringify([...userWords])) }
  catch { /* localStorage в CEF может быть запрещён */ }
}

function addToSpeller(key) {
  try { (HAS_CYR.test(key) ? spellerRu : spellerEn).add(key) }
  catch { /* личный словарь nspell — не критично */ }
}

// Тяжёлая инициализация (~1 c CPU): вызывать после первого рендера диалога
export function ensureDicts() {
  if (spellerRu) return
  spellerRu = nspell(ruAff, ruDic)
  spellerEn = nspell(enAff, enDic)
  for (const w of userWords) addToSpeller(w)
}

export function isReady() {
  return !!spellerRu
}

function isCorrect(word) {
  if (word.length < 2) return true
  // Аббревиатуры капсом (ЛДСП, MDF, LED) не подсвечиваем
  if (word === word.toUpperCase()) return true
  const key = word.toLowerCase()
  if (userWords.has(key)) return true
  if (correctness.has(key)) return correctness.get(key)
  let ok
  if (HAS_CYR.test(key) && HAS_LAT.test(key)) ok = true
  else {
    const speller = HAS_CYR.test(key) ? spellerRu : spellerEn
    // Составные слова через дефис/апостроф верны, если верна каждая часть
    ok = !speller || key.split(/['’-]/).every((part) => !part || speller.correct(part))
  }
  correctness.set(key, ok)
  return ok
}

// Массив диапазонов { start, end } опечаток в тексте поля
export function checkText(text) {
  if (!spellerRu || !text) return []
  const found = []
  WORD_RE.lastIndex = 0
  let m
  while ((m = WORD_RE.exec(text)) !== null) {
    if (!isCorrect(m[0])) found.push({ start: m.index, end: m.index + m[0].length })
  }
  return found
}

export function suggestFor(word) {
  if (!spellerRu || !word) return []
  const speller = HAS_CYR.test(word) ? spellerRu : spellerEn
  try { return (speller.suggest(word) || []).slice(0, 6) }
  catch { return [] }
}

export function addUserWord(word) {
  const key = (word || '').toLowerCase()
  if (!key) return
  userWords.add(key)
  correctness.set(key, true)
  saveUserWords()
  addToSpeller(key)
}
