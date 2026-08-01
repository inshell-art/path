(() => {
  const snapshot = window.PATH_ARTIFACT_PREVIEW;
  if (!snapshot) {
    document.getElementById("runtime-status").textContent = "Snapshot missing";
    return;
  }

  const state = { query: "", stage: "ALL", view: "gallery" };
  const grid = document.getElementById("token-grid");
  const empty = document.getElementById("empty-state");
  const count = document.getElementById("result-count");
  const dialog = document.getElementById("token-detail");

  const short = (value, left = 10, right = 8) => `${value.slice(0, left)}…${value.slice(-right)}`;

  function addDefinition(list, label, value, title = value) {
    const row = document.createElement("div");
    const term = document.createElement("dt");
    const data = document.createElement("dd");
    term.textContent = label;
    data.textContent = value;
    data.title = title;
    row.append(term, data);
    list.append(row);
  }

  function progressRow(label, value, quota) {
    const row = document.createElement("div");
    row.className = "progress-row";
    const name = document.createElement("span");
    name.textContent = label;
    const track = document.createElement("div");
    track.className = "progress-track";
    const fill = document.createElement("div");
    fill.className = "progress-fill";
    fill.style.width = `${quota === 0 ? 0 : Math.min(100, (value / quota) * 100)}%`;
    track.append(fill);
    const amount = document.createElement("span");
    amount.textContent = `${value}/${quota}`;
    row.append(name, track, amount);
    return row;
  }

  function showDetail(token) {
    document.getElementById("detail-label").textContent = token.label;
    document.getElementById("detail-title").textContent = `PATH #${token.tokenId}`;
    const image = document.getElementById("detail-image");
    image.src = token.image;
    image.alt = `PATH #${token.tokenId}, ${token.stage} stage`;

    const traits = document.getElementById("detail-traits");
    traits.textContent = "";
    for (const attribute of token.attributes) addDefinition(traits, attribute.trait_type, attribute.value);

    const artifact = document.getElementById("detail-artifact");
    artifact.textContent = "";
    addDefinition(artifact, "SVG SHA-256", short(token.svgSha256), token.svgSha256);
    addDefinition(artifact, "tokenURI SHA-256", short(token.tokenUriSha256), token.tokenUriSha256);
    addDefinition(artifact, "SVG bytes", token.svgBytes.toLocaleString());
    addDefinition(artifact, "tokenURI bytes", token.tokenUriBytes.toLocaleString());
    addDefinition(artifact, "Glyph paths", String(token.pathDefinitions));
    addDefinition(artifact, "Glyph uses", String(token.glyphUses));

    const download = document.getElementById("detail-download");
    download.href = token.image;
    download.download = `path-${token.tokenId}.svg`;
    dialog.showModal();
  }

  function cardFor(token) {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "token-card";
    card.dataset.tokenId = token.tokenId;
    card.setAttribute("aria-label", `Inspect PATH #${token.tokenId}, ${token.label}`);

    const image = document.createElement("img");
    image.src = token.image;
    image.alt = `PATH #${token.tokenId}, ${token.stage} stage`;
    image.loading = "eager";

    const body = document.createElement("div");
    body.className = "card-body";
    const title = document.createElement("div");
    title.className = "card-title";
    const name = document.createElement("strong");
    name.textContent = `PATH #${token.tokenId}`;
    const stage = document.createElement("span");
    stage.className = "stage";
    stage.textContent = token.stage;
    title.append(name, stage);
    const label = document.createElement("div");
    label.className = "card-label";
    label.textContent = token.label;
    body.append(
      title,
      label,
      progressRow("THOUGHT", token.progress.thought, snapshot.quotas.thought),
      progressRow("WILL", token.progress.will, snapshot.quotas.will),
      progressRow("AWA", token.progress.awa, snapshot.quotas.awa)
    );
    card.append(image, body);
    card.addEventListener("click", () => showDetail(token));
    return card;
  }

  function render() {
    const query = state.query.trim().toLowerCase();
    const visible = snapshot.examples.filter((token) => {
      const searchable = [
        token.tokenId,
        token.label,
        token.stage,
        ...token.attributes.flatMap((attribute) => [attribute.trait_type, attribute.value])
      ].join(" ").toLowerCase();
      return (!query || searchable.includes(query)) && (state.stage === "ALL" || token.stage === state.stage);
    });

    grid.textContent = "";
    grid.dataset.view = state.view;
    for (const token of visible) grid.append(cardFor(token));
    count.textContent = `${visible.length} ${visible.length === 1 ? "token" : "tokens"}`;
    empty.hidden = visible.length !== 0;
  }

  document.getElementById("runtime-status").textContent = `${snapshot.examples.length} verified states`;
  document.getElementById("source-commit").textContent = short(snapshot.source.repoCommit);
  document.getElementById("source-commit").title = snapshot.source.repoCommit;
  document.getElementById("runtime-hash").textContent = short(snapshot.localChain.runtimeCodeHash);
  document.getElementById("runtime-hash").title = snapshot.localChain.runtimeCodeHash;
  document.getElementById("renderer-release").textContent = short(snapshot.renderer.glyphSliceSha256);
  document.getElementById("renderer-release").title = snapshot.renderer.glyphSliceSha256;
  document.getElementById("quota-summary").textContent = `${snapshot.quotas.thought} / ${snapshot.quotas.will} / ${snapshot.quotas.awa}`;

  document.getElementById("search").addEventListener("input", (event) => {
    state.query = event.target.value;
    render();
  });
  document.getElementById("stage-filter").addEventListener("change", (event) => {
    state.stage = event.target.value;
    render();
  });
  for (const button of document.querySelectorAll(".view-control [data-view]")) {
    button.addEventListener("click", () => {
      state.view = button.dataset.view;
      for (const item of document.querySelectorAll(".view-control [data-view]")) {
        item.setAttribute("aria-pressed", String(item === button));
      }
      render();
    });
  }
  document.getElementById("detail-close").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });

  render();
})();
