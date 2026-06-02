import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://useTether.dev";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Tether — Local AI Agent Debugger & LLM Observability for macOS",
    template: "%s | Tether",
  },
  description:
    "Intercept, inspect, and replay every LLM call from your AI agents — entirely on your Mac. Local proxy for OpenAI, Anthropic & Ollama. No SDK changes, no data leaves the machine.",
  keywords: [
    "AI agent debugger",
    "LLM observability",
    "local AI proxy",
    "OpenAI proxy macOS",
    "Anthropic proxy",
    "agent tracing tool",
    "LLM call inspector",
    "AI debugging macOS",
    "local AI observability",
    "agent replay",
  ],
  authors: [{ name: "Tether" }],
  creator: "Tether",
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  icons: {
    icon: [{ url: "/Tether.PNG", sizes: "1024x1024", type: "image/png" }],
    shortcut: [{ url: "/Tether.PNG", sizes: "1024x1024", type: "image/png" }],
    apple: [{ url: "/Tether.PNG", sizes: "1024x1024", type: "image/png" }],
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Tether",
    title: "Tether — Local AI Agent Debugger for macOS",
    description:
      "Intercept & replay every LLM call from your AI agents. Local proxy, zero SDK changes, 100% private. Free alpha for macOS.",
    images: [
      {
        url: "/Tether.PNG",
        width: 1024,
        height: 1024,
        alt: "Tether app icon",
      },
    ],
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Tether — Local AI Agent Debugger for macOS",
    description:
      "Intercept & replay every LLM call from your AI agents. Local proxy, zero SDK changes, 100% private.",
    images: ["/Tether.PNG"],
  },
  alternates: {
    canonical: SITE_URL,
  },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#organization`,
      name: "Tether",
      url: SITE_URL,
      description:
        "Local-first observability and debugging tool for AI agents and LLM applications on macOS.",
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${SITE_URL}/#app`,
      name: "Tether",
      applicationCategory: "DeveloperApplication",
      operatingSystem: "macOS 13+",
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
        description: "Free during alpha",
      },
      publisher: { "@id": `${SITE_URL}/#organization` },
      description:
        "Tether intercepts every LLM call from your AI agents, visualizes complex agent trees, and lets you replay or mock responses — entirely locally on your Mac. Supports OpenAI, Anthropic, Ollama, LangChain, LangGraph, and more.",
      featureList: [
        "Local LLM proxy — zero SDK changes",
        "Real-time agent trace visualization",
        "Request/response time-travel replay",
        "Response mocking for offline testing",
        "API key storage in macOS Keychain",
        "Air-gapped — no data leaves the machine",
      ],
      screenshot: `${SITE_URL}/Tether.PNG`,
    },
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: SITE_URL,
      name: "Tether",
      publisher: { "@id": `${SITE_URL}/#organization` },
    },
    {
      "@type": "HowTo",
      "@id": `${SITE_URL}/#howto`,
      name: "How to debug AI agents with Tether",
      description: "Set up Tether to intercept, visualize, and replay LLM calls from any AI agent in three steps.",
      totalTime: "PT2M",
      step: [
        {
          "@type": "HowToStep",
          position: 1,
          name: "Point the base_url",
          text: "Change your AI client's base_url to http://localhost:8080/v1. This is the only code change required. Works with any OpenAI-compatible SDK.",
        },
        {
          "@type": "HowToStep",
          position: 2,
          name: "Run your agent",
          text: "Run your agent as normal. Every LLM request is automatically intercepted, cached, and streamed into the visual tree in real time.",
        },
        {
          "@type": "HowToStep",
          position: 3,
          name: "Inspect and replay",
          text: "Open the canvas, click any node to inspect its full request and response, rewrite its output, and replay the chain from that point to test fixes.",
        },
      ],
    },
    {
      "@type": "FAQPage",
      mainEntity: [
        {
          "@type": "Question",
          name: "How does Tether intercept LLM calls without SDK changes?",
          acceptedAnswer: {
            "@type": "Answer",
            text: "Tether runs a local HTTP proxy on your machine. You point your AI client's base_url at http://localhost:8080/v1 — that's the only change required. Tether forwards requests to the real provider and records everything locally.",
          },
        },
        {
          "@type": "Question",
          name: "Does Tether send my prompts or API keys to the cloud?",
          acceptedAnswer: {
            "@type": "Answer",
            text: "No. Tether is fully air-gapped. Your prompts, responses, and API keys never leave your Mac. API keys are encrypted in the macOS Keychain.",
          },
        },
        {
          "@type": "Question",
          name: "Which LLM providers does Tether support?",
          acceptedAnswer: {
            "@type": "Answer",
            text: "Tether supports OpenAI, Anthropic, Ollama, LM Studio, and any provider that accepts an OpenAI-compatible base_url. It also works with LangChain, LangGraph, LlamaIndex, and similar frameworks.",
          },
        },
        {
          "@type": "Question",
          name: "Is Tether free?",
          acceptedAnswer: {
            "@type": "Answer",
            text: "Yes. Tether is free during the alpha period. The core proxy is open source.",
          },
        },
      ],
    },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
