#!/usr/bin/env -S deno run --allow-all

import * as path from "jsr:@std/path";
import { Webview } from "jsr:@webview/webview@0.9.0";

const html = await Deno.readTextFile(
  path.join(import.meta.dirname!, "index.html")
);

const webview = new Webview();
webview.title = "Boop";
webview.bind("sendMessage", async (message: string) => {
  await Deno.writeTextFile(`${Deno.env.get("HOME")}/server.log`, message, {
    append: true,
  });
});
webview.navigate(`data:text/html,${encodeURIComponent(html)}`);
webview.run();
