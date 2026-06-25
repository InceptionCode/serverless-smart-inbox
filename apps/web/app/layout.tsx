import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Smart Inbox — Sentiment Console",
  description: "Real-time sentiment monitoring for incoming messages, powered by Amazon Comprehend.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
