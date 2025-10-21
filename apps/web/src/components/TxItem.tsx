"use client";

import { RiExternalLinkLine } from "react-icons/ri";
import {  formatEth,  formatTimestamp, truncateAddress } from "@/utils/format";
import { type AggregatedTransaction, type TransactionCategory } from "@/lib/blockscout/transactionAggregator";

interface TransactionItemProps {
  tx: AggregatedTransaction;
  walletAddress: `0x${string}`;
}

const getTxTypeLabel = (category: TransactionCategory): string => {
  switch (category) {
    case 'deposit':
      return 'Funds Received';
    case 'execute_single':
      return 'Single Payment';
    case 'execute_batch':
      return 'Batch Payment';
    case 'intent_recurring_batch':
      return 'Recurring Batch Payment';
    case 'intent_recurring_single':
      return 'Recurring Single Payment';
    case 'intent_created':
      return 'Recurring Payment Created';
    case 'intent_cancelled':
      return 'Recurring Payment Cancelled';
    case 'wallet_deployed':
      return 'Wallet Deployed';
    default:
      return 'Transaction';
  }
};

const getTxTypeIcon=(category: TransactionCategory): React.ReactNode => {
  switch (category) {
    case 'deposit':
      return <RiExternalLinkLine />;
    case 'execute_single':
      return <RiExternalLinkLine />;
    case 'execute_batch':
      return <RiExternalLinkLine />;
    case 'intent_recurring_batch':
      return <RiExternalLinkLine />;
    case 'intent_recurring_single':
      return <RiExternalLinkLine />;
    case 'intent_created':
      return <RiExternalLinkLine />;
    case 'intent_cancelled':
      return <RiExternalLinkLine />;
    case 'wallet_deployed':
      return <RiExternalLinkLine />;
    default:
      return <RiExternalLinkLine />;
  }
};


export default function TransactionItem({
  tx,
  walletAddress,
}: TransactionItemProps) {
  const valueEth = formatEth(tx.value);
  const gasEth = formatEth(tx.gasUsed ?? 0n);
  const label = getTxTypeLabel(tx.category);
  
  // Format timestamp
  const formattedDate = formatTimestamp(tx.timestamp);
  const explorerUrl = `https://base-sepolia.blockscout.com/tx/${tx.hash}`;

  // Render different content based on transaction type
  const renderDetails = () => {
    switch (tx.category) {
      case "intent_created":
      case "intent_cancelled":
        return (
          <div className="space-y-1">
            {tx.intentId && (
              <div className="font-medium text-xs">
                Intent: {truncateAddress(tx.intentId)}
              </div>
            )}
            {tx.description && (
              <div className="text-xs text-muted-foreground">
                {tx.description}
              </div>
            )}
          </div>
        );

      case "intent_recurring_single":
      case "intent_recurring_batch":
        return (
          <div className="space-y-1">
            {tx.transactionCount !== undefined && (
              <div className="text-xs text-muted-foreground">
                Payment #{tx.transactionCount + 1}
              </div>
            )}
            {tx.recipients && tx.recipients.length > 0 && (
              <div className="text-xs text-muted-foreground">
                To {tx.recipients.length} recipient(s)
              </div>
            )}
            {tx.value > 0n && (
              <div className="text-xs font-medium">
                {valueEth} ETH
              </div>
            )}
          </div>
        );

      case "execute_batch":
        return (
          <div className="space-y-1">

              <div className="text-xs text-muted-foreground">
                Recipients: {tx.recipients?.length}
              </div>
            <div className="text-xs text-muted-foreground">
                Total value: {valueEth} ETH 
              </div>
           
          </div>
        );

      case "execute_single":
        return (
          <div className="space-y-1">
            <div className="text-xs text-muted-foreground">
              To: {truncateAddress(tx.to)}
            </div>
            {tx.value > 0n && (
              <div className="text-xs text-muted-foreground">
              value:  {valueEth} ETH
              </div>
            )}
          </div>
        );

      case "deposit":
        return (
          <div className="text-xs text-muted-foreground">
            From: {truncateAddress(tx.from)}
          </div>
        );
      
      case "wallet_deployed":
        return (
          <div className="text-xs text-muted-foreground">
            {tx.description || "Smart wallet created"}
          </div>
        );

      default:
        if (tx.description) {
          return (
            <div className="text-xs text-muted-foreground">
              {tx.description}
            </div>
          );
        }
        return null;
    }
  };

  return (
    <div
      className={`
        hover:bg-sidebar-accent hover:text-sidebar-accent-foreground
        flex flex-col gap-2.5 border-b p-4 text-sm leading-tight
        last:border-b-0 transition-colors `}>
      {/* Header Row */}
      <div className="flex justify-between items-start w-full gap-2">
        <div className="flex items-center gap-2 flex-1 min-w-0">
          <div className="flex flex-col min-w-0 flex-1">
            <span className={`font-semibold truncate`}>
              {label}
            </span>
          </div>
        </div>
        
        {/* <div className="font-medium whitespace-nowrap text-right">
          {tx.category === 'deposit' ? '+' : tx.category.startsWith('intent_') && !tx.category.includes('created') && !tx.category.includes('cancelled') ? '' : tx.value > 0n ? '-' : ''}
          {tx.value !== 0n && ` ${valueEth} ETH`}
        </div> */}
      </div>

      {/* Details */}
      {renderDetails()}

      {/* Footer Row */}
      <div className="flex justify-between items-center w-full text-xs text-muted-foreground">
        <div>{formattedDate}</div>
          <a
          href={explorerUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-1 text-blue-500 hover:underline"
        >
      
          <span>View</span>
          <RiExternalLinkLine />
        </a>
      </div>


    {  tx.gasUsed !== undefined && tx.gasUsed > 0n && (
        <div className="text-xs opacity-50">
          Gas: {gasEth} ETH
        </div>)}
      
    </div>
  );
}