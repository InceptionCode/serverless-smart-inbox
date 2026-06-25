import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        base: "#0f1117",
        panel: "#1a1d27",
        panel2: "#22263a",
        line: "#2e3347",
        text: "#e2e8f0",
        muted: "#64748b",
        live: "#22c55e",
        neg: "#ef4444",
        pos: "#4ade80",
      },
      fontFamily: {
        display: ["ui-monospace", "SFMono-Regular", "monospace"],
      },
      animation: {
        livepulse: "livepulse 2s ease-in-out infinite",
        sweep: "sweep 3s linear infinite",
      },
      keyframes: {
        livepulse: {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.3" },
        },
        sweep: {
          "0%": { transform: "translateX(-100%)" },
          "100%": { transform: "translateX(400%)" },
        },
      },
    },
  },
  plugins: [],
};

export default config;
