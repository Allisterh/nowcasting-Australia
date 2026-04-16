import { formatDate } from "@/lib/format";

interface StalenessBannerProps {
  generatedAt: string;
  thresholdDays?: number;
}

export default function StalenessBanner({
  generatedAt,
  thresholdDays = 10,
}: StalenessBannerProps) {
  const generated = new Date(generatedAt);
  const now = new Date();
  const ageDays = Math.floor((now.getTime() - generated.getTime()) / 86400000);

  if (ageDays < thresholdDays) return null;

  return (
    <div className="mb-4 px-3 py-2 border border-border-heavy bg-panel text-xs">
      Last updated {ageDays} days ago ({formatDate(generatedAt)}) — data is currently stale.
    </div>
  );
}
