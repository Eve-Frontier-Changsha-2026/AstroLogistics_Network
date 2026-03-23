import { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { Layout } from './components/layout/Layout';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const BountyBoardPage = lazy(() => import('./pages/BountyBoardPage'));
const ContractDetailPage = lazy(() => import('./pages/ContractDetailPage'));
const FuelStationPage = lazy(() => import('./pages/FuelStationPage'));
const TransportPage = lazy(() => import('./pages/TransportPage'));
const GuildPage = lazy(() => import('./pages/GuildPage'));
const ThreatMapPage = lazy(() => import('./pages/ThreatMapPage'));
const StorageDetailPage = lazy(() => import('./pages/StorageDetailPage'));

function Fallback() {
  return <div className="text-gray-400 py-12 text-center">Loading...</div>;
}

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Suspense fallback={<Fallback />}><DashboardPage /></Suspense>} />
        <Route path="storage/:storageId" element={<Suspense fallback={<Fallback />}><StorageDetailPage /></Suspense>} />
        <Route path="bounty" element={<Suspense fallback={<Fallback />}><BountyBoardPage /></Suspense>} />
        <Route path="bounty/:contractId" element={<Suspense fallback={<Fallback />}><ContractDetailPage /></Suspense>} />
        <Route path="fuel" element={<Suspense fallback={<Fallback />}><FuelStationPage /></Suspense>} />
        <Route path="transport" element={<Suspense fallback={<Fallback />}><TransportPage /></Suspense>} />
        <Route path="guild" element={<Suspense fallback={<Fallback />}><GuildPage /></Suspense>} />
        <Route path="threats" element={<Suspense fallback={<Fallback />}><ThreatMapPage /></Suspense>} />
      </Route>
    </Routes>
  );
}
