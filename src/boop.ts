#!/usr/bin/env -S deno run --allow-all --unstable-ffi

import presetTailwind from "https://esm.sh/@twind/preset-tailwind@1.1.4";
import * as twind from "https://esm.sh/@twind/core@1.1.3";
import { WebUI } from "https://deno.land/x/webui@2.4.4/mod.ts";

const body = `
<html>
  <head>
    <title>Boop Bum</title>
  </head>
  <body>
    <p class="m-8 text-red-500">Boop is tiny and small!</p>
    <script src="webui.js"></script>
  </body>
</html>
`;

twind.install({ presets: [presetTailwind(), {}] });
const window = new WebUI();
const { html, css } = twind.extract(body);
window.show(html.replace("</head>", `<style data-twind>${css}</style></head>`));

await WebUI.wait();
