#!/usr/bin/env -S deno run --allow-all --unstable-ffi

import presetTailwind from "https://esm.sh/@twind/preset-tailwind@1.1.4";
import * as twind from "https://esm.sh/@twind/core@1.1.3";
import { Webview } from "jsr:@webview/webview@0.9.0";

const body = `
<html>
  <head>
    <title>Boop Bum</title>
  </head>
  <body>
    <p class="m-8 text-red-500">Boop is tiny and small!</p>
    <div class="m-8" id="app">
      <button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" @click="greet">{{ message }}</button>
    </div>
    <script src="webui.js"></script>
    <script type="module">
import { createApp, ref } from "https://unpkg.com/vue@3/dist/vue.esm-browser.js";

createApp({
  setup() {
    function greet(event) {
      message.value = "Clicked!";
    }

    const message = ref("Hello vue!");
    return { greet, message };
  }
}).mount("#app");
    </script>
  </body>
</html>
`;

twind.install({ presets: [presetTailwind(), {}] });
const webview = new Webview();
const { html, css } = twind.extract(body);
const html_ = html.replace(
  "</head>",
  `<style data-twind>${css}</style></head>`
);
webview.navigate(`data:text/html,${encodeURIComponent(html_)}`);

webview.run();
