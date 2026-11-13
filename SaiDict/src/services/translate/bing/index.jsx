import { fetch, Body } from '@tauri-apps/api/http';
import { DEFAULT_EDGE_USER_AGENT } from '../../../utils/http';

// New endpoint: edge.microsoft.com/translate/translatetext is token-free.
// The old api-edge.cognitive.microsofttranslator.com endpoint is deprecated.
const MS_TRANSLATE_URL = 'https://edge.microsoft.com/translate/translatetext?isEnterpriseClient=false&';
// Language detection reuses the same endpoint, just with a `to` parameter.
const MS_DETECT_URL = MS_TRANSLATE_URL + 'to=en';

export async function translate(text, from, to) {
    if (!text) return '';

    const targetLang = to;
    const url = MS_TRANSLATE_URL + 'to=' + targetLang;

    const res = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'User-Agent': DEFAULT_EDGE_USER_AGENT,
        },
        // Send a plain string array. `from` is intentionally omitted so the
        // endpoint auto-detects the source language (matches the reference
        // translateText, which uses only `to=` in the URL).
        body: Body.json([text]),
    });

    if (res.ok) {
        const result = res.data;
        if (Array.isArray(result) && result[0] && result[0].translations) {
            return result[0].translations[0].text.trim();
        }
        // Unexpected structure — surface it for upstream handling.
        throw JSON.stringify(result);
    } else {
        throw `Http Request Error\nHttp Status: ${res.status}\n${JSON.stringify(res.data)}`;
    }
}

export * from './Config';
export * from './info';
