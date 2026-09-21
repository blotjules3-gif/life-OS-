import assert from "node:assert/strict";
import { namesFromRows } from "./worker.js";
let n = 0; const t = (name, fn) => { fn(); n++; };

const head = ["Concurrent", "Nouveau nom LifeOS", "Nom descriptif", "Ce que ça fait", "État"];

t("lit un renommage", () => {
  const r = namesFromRows([[head, ["Duolingo", "Trilingo", "Langues", "x", "y"]]]);
  assert.equal(r.names["Langues"], "Trilingo");
});
t("colonnes deplacees", () => {
  const h = ["Nom descriptif", "État", "Nouveau nom LifeOS"];
  const r = namesFromRows([[h, ["Langues", "ok", "LinguaTrio"]]]);
  assert.equal(r.names["Langues"], "LinguaTrio");
});
t("nom vide refuse", () => {
  const r = namesFromRows([[head, ["Duolingo", "   ", "Langues"]]]);
  assert.equal(r.names["Langues"], undefined);
  assert.equal(r.problems.length, 1);
});
t("nom trop long refuse", () => {
  const r = namesFromRows([[head, ["Duolingo", "x".repeat(41), "Langues"]]]);
  assert.equal(r.names["Langues"], undefined);
});
t("outil inconnu ignore", () => {
  const r = namesFromRows([[head, ["X", "Truc", "Outil qui n'existe pas"]]]);
  assert.deepEqual(r.names, {});
});
t("table sans les bonnes colonnes ignoree", () => {
  const r = namesFromRows([[["a", "b"], ["Langues", "Z"]]]);
  assert.deepEqual(r.names, {});
});
t("espaces nettoyes", () => {
  const r = namesFromRows([[head, ["Duolingo", "  Tri   lingo ", "Langues"]]]);
  assert.equal(r.names["Langues"], "Tri lingo");
});
t("les 4 lignes hors categories ne sont pas des outils de l'app", () => {
  const r = namesFromRows([[head, ["Alarmy", "Réveil", "Réveil"]]]);
  assert.deepEqual(r.names, {});
});
console.log(`${n} controles OK`);
