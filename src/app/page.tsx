import { loadDashboardData } from "@/lib/data";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import StalenessBanner from "@/components/StalenessBanner";
import HeadlineCard from "@/components/HeadlineCard";
import GdpHistoryChart from "@/components/GdpHistoryChart";
import VintageChart from "@/components/VintageChart";
import IndicatorGrid from "@/components/IndicatorGrid";

export default function Home() {
  const data = loadDashboardData();
  return (
    <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8">
      <StalenessBanner generatedAt={data.latest.generated_at} />
      <Header generatedAt={data.latest.generated_at} />
      <HeadlineCard latest={data.latest} gdp={data.gdp} />
      <GdpHistoryChart gdp={data.gdp} latest={data.latest} />
      <VintageChart nowcasts={data.nowcasts} />
      <IndicatorGrid indicators={data.indicators} />
      <p className="text-label text-sm">More sections landing in subsequent tasks.</p>
      <Footer />
    </main>
  );
}
