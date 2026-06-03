import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Hajar — Autonomous DeFi Guardian on Somnia",
  description:
    "A three-tier autonomous security layer for DeFi: deterministic circuit breakers + consensus-verified AI risk scoring on Somnia's Agentic L1.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
