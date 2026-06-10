/**
 * Hajar mark — a pixel guardian shield with a check (protected, verified). On-theme with the
 * 8bitcn pixel UI: sharp edges (shapeRendering crispEdges), chunky dark outline, retro-green fill.
 */
export default function Logo({ size = 28, accent = "#4ee08a", ink = "#0b0d0e" }: { size?: number; accent?: string; ink?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      shapeRendering="crispEdges"
      aria-label="Hajar"
      role="img"
    >
      {/* shield body */}
      <path d="M4 3 H20 V12 L12 22 L4 12 Z" fill={accent} stroke={ink} strokeWidth="2" strokeLinejoin="miter" />
      {/* inner notch (gives it a pixel-plate look) */}
      <path d="M7 6 H17 V12 L12 18 L7 12 Z" fill="none" stroke={ink} strokeWidth="1.4" opacity="0.55" />
      {/* check mark */}
      <path d="M8.5 11.5 L11 14 L15.5 8.5" stroke={ink} strokeWidth="2.4" strokeLinecap="square" strokeLinejoin="miter" />
    </svg>
  );
}
