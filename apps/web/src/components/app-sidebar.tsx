"use client";

import * as React from "react";
import { BiFilterAlt } from "react-icons/bi";
import { AiOutlineLoading3Quarters } from "react-icons/ai";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  useSidebar,
} from "@/components/ui/sidebar";
import { useAggregatedTransactions } from "@/lib/blockscout/useBlockScout";
import TransactionItem from "./TxItem";
import { type TransactionCategory } from "@/lib/blockscout/transactionAggregator";

type AppSidebarRightProps = {
  walletAddress: `0x${string}`;
};

// Filter options - Updated to match new categories
const TX_TYPE_FILTERS: { value: TransactionCategory | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "deposit", label: "Deposits" },
  { value: "execute_single", label: "Single Payments" },
  { value: "execute_batch", label: "Batch Payments" },
  { value: "intent_created", label: "Intents Created" },
  { value: "intent_cancelled", label: "Intents Cancelled" },
  { value: "intent_recurring_single", label: "Automated Payments" },
  { value: "intent_recurring_batch", label: "Automated Batch Payments" },
  { value: "wallet_deployed", label: "Wallet Deployed" },
];

export function AppSidebar({
  walletAddress,
  ...props
}: AppSidebarRightProps & React.ComponentProps<typeof Sidebar>) {
  const { setOpen } = useSidebar();
  const [txTypeFilter, setTxTypeFilter] = React.useState<TransactionCategory | "all">("all");

  // Fetch aggregated transactions
  const {
    transactions,
    isLoading,
    isError,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useAggregatedTransactions({
    address: walletAddress,
  });

  
  // Filter transactions based on selected filter
  const filteredTxs = React.useMemo(() => {
    if (txTypeFilter === "all") return transactions;
    return transactions.filter(tx => tx.category === txTypeFilter);
  }, [transactions, txTypeFilter]);

  // Infinite scroll handler
  const observerTarget = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) {
          fetchNextPage();
        }
      },
      { threshold: 1.0 }
    );

    const currentTarget = observerTarget.current;
    if (currentTarget) {
      observer.observe(currentTarget);
    }

    return () => {
      if (currentTarget) {
        observer.unobserve(currentTarget);
      }
    };
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  return (
    <Sidebar
      collapsible="icon"
      className="overflow-hidden *:data-[sidebar=sidebar]:flex-row"
      {...props}
    >
      <Sidebar
        collapsible="none"
        className="hidden flex-1 md:flex"
        style={{ scrollbarWidth: "none" }}
      >
        <SidebarHeader className="gap-3.5 border-b p-4">
          <div className="flex w-full items-center justify-between">
            <div className="text-foreground text-base font-medium">
              Transactions
            </div>
            
            {/* Filter Dropdown */}
            <div className="relative">
              <select
                value={txTypeFilter}
                onChange={(e) => setTxTypeFilter(e.target.value as TransactionCategory | "all")}
                className="appearance-none bg-sidebar-accent text-sidebar-foreground text-xs px-3 py-1.5 pr-8 rounded-md border border-sidebar-border focus:outline-none focus:ring-2 focus:ring-sidebar-ring"
              >
                {TX_TYPE_FILTERS.map((filter) => (
                  <option key={filter.value} value={filter.value}>
                    {filter.label}
                  </option>
                ))}
              </select>
              <BiFilterAlt className="absolute right-2 top-1/2 -translate-y-1/2 pointer-events-none text-xs" />
            </div>
          </div>

          {/* Stats */}
          <div className="flex gap-2 text-xs text-muted-foreground">
            <span>{filteredTxs.length} transactions</span>
          </div>
        </SidebarHeader>

        <SidebarContent
          className="[&::-webkit-scrollbar]:hidden"
          style={{ msOverflowStyle: "none", scrollbarWidth: "none" }}
        >
          <SidebarGroup className="px-0">
            <SidebarGroupContent>
              {isLoading ? (
                <div className="flex items-center justify-center p-8">
                  <AiOutlineLoading3Quarters className="animate-spin text-2xl text-muted-foreground" />
                </div>
              ) : isError ? (
                <div className="p-4 text-center text-sm text-red-600">
                  Failed to load transactions
                </div>
              ) : filteredTxs.length === 0 ? (
                <div className="p-4 text-center text-sm text-muted-foreground">
                  No transactions found
                </div>
              ) : (
                <>
                  {filteredTxs.map((tx, i) => (
                    <TransactionItem
                      key={`${tx.hash}-${i}`}
                      tx={tx}
                      walletAddress={walletAddress}
                    />
                  ))}

                  {/* Infinite scroll trigger */}
                  <div ref={observerTarget} className="h-4" />

                  {/* Loading indicator */}
                  {isFetchingNextPage && (
                    <div className="flex items-center justify-center p-4">
                      <AiOutlineLoading3Quarters className="animate-spin text-lg text-muted-foreground" />
                    </div>
                  )}
                </>
              )}
            </SidebarGroupContent>
          </SidebarGroup>
        </SidebarContent>
      </Sidebar>
    </Sidebar>
  );
}